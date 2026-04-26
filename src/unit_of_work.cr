class Athena::ORM::UnitOfWork
  record Change, old : AORM::Mapping::Value?, new : AORM::Mapping::Value

  enum EntityState
    Managed
    New
    Detached
    Removed
  end

  # :nodoc:
  private class InsertBatch
    getter class_metadata : Mapping::ClassInterface
    getter entities : Array(AORM::Entity)

    def initialize(@class_metadata : Mapping::ClassInterface, @entities : Array(AORM::Entity)); end

    def self.batch_by_entity_type(em : AORM::EntityManagerInterface, entities : Array(AORM::Entity)) : Array(self)
      current_metadata = nil
      batches = [] of InsertBatch
      batch_index = -1

      entities.each do |entity|
        entity_metadata = em.class_metadata entity.class

        if current_metadata.try(&.entity_class) != entity_metadata.entity_class || (!entity_metadata.id_generator.is_a?(ID::AssignedGenerator))
          current_metadata = entity_metadata
          batches << new(entity_metadata, [entity])
          batch_index += 1

          next
        end

        batches[batch_index].entities << entity
      end

      batches
    end
  end

  def self.id_hash_by_identifier(identifier : Hash(String | Number, _)) : String
    String.build do |io|
      first = true
      identifier.each_value do |v|
        io << ' ' unless first
        first = false

        raw = v.is_a?(AORM::Mapping::Value) ? v.value : v

        case raw
        when ::Bool then io << (raw ? "1" : "")
        when ::Enum then io << raw.value
        else             io << raw
        end
      end
    end
  end

  @identity_map = Hash(AORM::Entity.class, Hash(String, AORM::Entity)).new.compare_by_identity

  # Stores the value of each of an entity's PK
  @entity_identifiers = Hash(AORM::Entity, Hash(String, AORM::Mapping::Value)).new.compare_by_identity

  @entity_states = Hash(AORM::Entity, EntityState).new.compare_by_identity

  # Pending entity deletions
  @entity_deletions = Set(AORM::Entity).new.compare_by_identity

  # Pending entity insertions
  @entity_insertions = Set(AORM::Entity).new.compare_by_identity

  # Pending entity updates
  @entity_updates = Set(AORM::Entity).new.compare_by_identity

  @entity_persisters = Hash(AORM::Entity.class, AORM::Persisters::Entity::Interface).new.compare_by_identity
  @collection_persisters = Hash(String, Athena::ORM::Persisters::Collection::Interface).new

  @original_entity_data = Hash(AORM::Entity, Hash(String, Mapping::Value)).new do |hash, key|
    hash[key] = Hash(String, Mapping::Value).new
  end.compare_by_identity
  @entity_change_sets = Hash(AORM::Entity, Hash(String, Change)).new.compare_by_identity
  @orphan_removals = Set(AORM::Entity).new.compare_by_identity

  @non_cascaded_new_detected_entities = Hash(AORM::Entity, Tuple(AORM::Mapping::Association, AORM::Entity)).new.compare_by_identity

  # Collections scheduled for deletion (cleared or owner removed)
  @collection_deletions = Set(AORM::PersistentCollectionInterface).new.compare_by_identity

  # Collections scheduled for update (elements added or removed)
  @collection_updates = Set(AORM::PersistentCollectionInterface).new.compare_by_identity

  # Collections that have been visited during changeset computation
  @visited_collections = Set(AORM::PersistentCollectionInterface).new.compare_by_identity

  # Per-collection list of entities flagged for removal during change-set computation; applied after the transaction commits, alongside snapshots.
  @pending_collection_element_removals = Hash(AORM::PersistentCollectionInterface, Array(AORM::Entity)).new.compare_by_identity

  # Per-entity changeset patches that must be applied as follow-up UPDATEs
  # after the main inserts run — needed when a FK can't be set during INSERT
  # because the referenced row hasn't been written yet (i.e. cyclic FKs).
  @extra_updates = Hash(AORM::Entity, Hash(String, Change)).new.compare_by_identity

  # ToOne associations whose target wasn't in the identity map at hydration time.
  # Resolved (eager-loaded) by the hydrator's `cleanup` after the main cursor closes — issuing a SELECT during hydration would conflict with the active result set on the same connection.
  # `target_id` nil means inverse side (load_one_to_one_entity); non-nil means owning side (find by FK).
  private record PendingToOneResolution,
    source : AORM::Entity,
    field_name : String,
    target_class : AORM::Entity.class,
    target_id : Hash(String, DB::Any)?

  @pending_to_one_resolutions = [] of PendingToOneResolution

  getter identifier_flattener : AORM::Utility::IdentifierFlattener { AORM::Utility::IdentifierFlattener.new(self, @em.metadata_factory) }

  def initialize(@em : AORM::EntityManagerInterface)
  end

  def commit : Nil
    # TODO: Ensure connected to primary

    # TODO: Handle eventing (preFlush)

    self.compute_changesets

    # Nothing to do
    if @entity_deletions.empty? && @entity_insertions.empty? && @entity_updates.empty? && @orphan_removals.empty? && @collection_deletions.empty? && @collection_updates.empty?
      # TODO: Handle eventing (onFlush/postFlush)

      self.post_commit_cleanup

      return
    end

    # TODO: Handle associations
    self.assert_that_there_are_no_unintentionally_non_persisted_associations

    @orphan_removals.each do |orphan|
      self.remove orphan
    end

    # TODO: Handle eventing (onFlush)

    @em.transaction do
      # Collection deletions (deletions of complete collections)
      @collection_deletions.each do |collection|
        # Deferred explicit tracked collections can be removed only when owning relation was persisted
        owner = collection.owner

        # TODO: Handle change tracking and dirty checks
      end

      @entity_insertions.each do |entity|
        # Perform entity insertions first, so that all new entities have their rows in the database
        # and can be referred to by foreign keys. The commit order only needs to take new entities
        # into account (new entities referring to other new entities), since all other types (entities
        # with updates or scheduled deletions) are currently not a problem, since they are already
        # in the database.
        self.execute_inserts @em.class_metadata entity.class
      end

      unless @entity_updates.empty?
        self.execute_updates
      end

      unless @extra_updates.empty?
        self.execute_extra_updates
      end

      # Handle collection updates after entity inserts
      @collection_updates.each do |collection|
        self.collection_persister(collection.association).update collection
      end

      unless @entity_deletions.empty?
        self.execute_deletions
      end
    rescue ex : ::Exception
      @em.close
      self.after_transaction_rolled_back
      raise ex
    end

    self.after_transaction_complete

    # Apply pending element removals, then snapshot
    @visited_collections.each do |collection|
      if pending = @pending_collection_element_removals[collection]?
        pending.each { |entity| collection.remove_element entity }
      end

      collection.take_snapshot
    end

    # TODO: Handle eventing (postFlush)

    self.post_commit_cleanup
  end

  private def after_transaction_rolled_back : Nil
    # TODO: CachedPersisters?
  end

  private def after_transaction_complete : Nil
    # TODO: CachedPersisters?
  end

  def scheduled_entity_insertions : Set(AORM::Entity)
    @entity_insertions
  end

  def scheduled_entity_deletions : Set(AORM::Entity)
    @entity_deletions
  end

  def scheduled_entity_updates : Set(AORM::Entity)
    @entity_updates
  end

  def assign_post_insert_id(entity : AORM::Entity, id) : Nil
    class_metadata = @em.class_metadata entity.class
    id_field = class_metadata.single_identifier_field_name
    id_value = self.convert_single_field_identifier_to_crystal_value class_metadata, id

    class_metadata.assign_identifier entity, id_field, id_value

    @entity_identifiers[entity] = {id_field => class_metadata.field_info[id_field].create_column_value(id_value).as Mapping::Value}
    @entity_states[entity] = :managed
    @original_entity_data[entity][id_field] = class_metadata.field_info[id_field].create_column_value id_value

    self.add_to_identity_map entity
  end

  private def convert_single_field_identifier_to_crystal_value(class_metadata : Mapping::ClassInterface, value : _)
    @em.connection.convert_to_crystal_value(
      value,
      class_metadata.type_of_field class_metadata.single_identifier_field_name
    )
  end

  private def assert_that_there_are_no_unintentionally_non_persisted_associations : Nil
    # Find entities that were detected as NEW through non-cascading associations
    # but were never scheduled for insertion (either explicitly or via cascade)
    entities_needing_cascade_persist = @non_cascaded_new_detected_entities.reject do |entity, _|
      @entity_insertions.includes?(entity)
    end

    @non_cascaded_new_detected_entities.clear

    return if entities_needing_cascade_persist.empty?

    raise "new entities found through relationships"
  end

  private def post_commit_cleanup : Nil
    @entity_insertions.clear
    @entity_updates.clear
    @entity_deletions.clear
    @entity_change_sets.clear
    @extra_updates.clear
    @orphan_removals.clear
    @collection_deletions.clear
    @collection_updates.clear
    @visited_collections.clear
    @pending_collection_element_removals.clear
  end

  private def execute_inserts(class_metadata : AORM::Mapping::ClassInterface) : Nil
    batched_by_type = InsertBatch.batch_by_entity_type @em, self.compute_insert_execution_order
    # TODO: Handle eventing

    batched_by_type.each do |batch|
      class_metadata = batch.class_metadata
      # TODO: Handle eventing

      persister = self.entity_persister class_metadata.entity_class

      batch.entities.each do |entity|
        persister.add_insert entity
        @entity_insertions.delete entity
      end

      persister.execute_inserts

      batch.entities.each do |entity|
        unless @entity_identifiers.has_key? entity
          self.add_to_entity_identifier_and_entity_map class_metadata, entity
        end

        # TODO: Handle eventing
      end
    end

    # TODO: Handle eventing (postPersist)
  end

  protected def compute_insert_execution_order : Array(AORM::Entity)
    sort = Internal::TopologicalSort.new

    @entity_insertions.each do |entity|
      sort.add_node entity
    end

    @entity_insertions.each do |entity|
      class_metadata = @em.class_metadata entity.class

      class_metadata.association_mappings.each_value do |assoc|
        # ManyToMany owning sides write to a join table after the row inserts,
        # so they don't constrain insertion order.
        next unless assoc.is_a?(Mapping::ToOneOwningSide)

        target = class_metadata.field_value(entity, assoc.field_name)
        next if target.nil?
        next unless target.is_a?(AORM::Entity)
        # Only enforce ordering when the target is also being inserted in this flush.
        next unless sort.has_node? target

        # If the FK is nullable we can break the cycle by writing NULL first and
        # patching it up via an extra update; if not, the edge is mandatory.
        join_column = assoc.join_columns.first?
        is_nullable = join_column.nil? || join_column.nullable.nil? || join_column.nullable == true

        sort.add_edge entity, target, is_nullable
      end
    end

    sort.sort
  end

  private def add_to_entity_identifier_and_entity_map(class_metadata : Mapping::ClassInterface, entity : AORM::Entity) : Nil
    identifier = Hash(String, AORM::Mapping::Value).new

    class_metadata.identifier.each do |id_field|
      orig_value = class_metadata.field_info[id_field].get_value entity

      value = nil
      if class_metadata.association_mappings.has_key?(id_field) && orig_value.is_a?(AORM::Entity)
        value = self.single_identifier_value orig_value
      end

      identifier[id_field] = Mapping::ColumnValue.new id_field, value || orig_value
      @original_entity_data[entity][id_field] = Mapping::ColumnValue.new id_field, orig_value
    end

    @entity_states[entity] = :managed
    @entity_identifiers[entity] = identifier

    self.add_to_identity_map entity
  end

  private def execute_updates : Nil
    @entity_updates.each do |entity|
      class_metadata = @em.class_metadata entity.class
      persister = self.entity_persister class_metadata.entity_class
      # TODO: Handle eventing (preUpdate)

      unless @entity_change_sets[entity]?.try &.empty?
        persister.update entity
      end

      @entity_updates.delete entity

      # TODO: Handle eventing (postUpdate)
    end
  end

  private def execute_deletions : Nil
    entities = self.compute_delete_execution_order
    # TODO: Handle eventing

    entities.each do |entity|
      self.remove_from_identity_map entity

      class_metadata = @em.class_metadata entity.class
      persister = self.entity_persister class_metadata.entity_class
      # TODO: Handle eventing

      persister.delete entity

      @entity_deletions.delete entity
      @entity_identifiers.delete entity
      @original_entity_data.delete entity
      @entity_states.delete entity

      # This entity after deletion treated as NEW, even if the obtained by a new entity because the old one went out of scope.
      # @entityStates[entity] = :new
      unless class_metadata.identifier_natural?
        class_metadata.field_info[class_metadata.identifier.first].set_value entity, nil
      end

      # TODO: Handle eventing
    end

    # TODO: Handle eventing
  end

  private def compute_delete_execution_order : Array(AORM::Entity)
    strongly_connected_components = Internal::StronglyConnectedComponents.new
    sort = Internal::TopologicalSort.new

    @entity_deletions.each do |entity|
      strongly_connected_components.add_node entity
      sort.add_node entity
    end

    # First, consider only "on delete cascade" associations between entities
    # and find strongly connected groups. Once we delete any one of the entities
    # in such a group, _all_ of the other entities will be removed as well. So,
    # we need to treat those groups like a single entity when performing delete
    # order topological sorting.
    @entity_deletions.each do |entity|
      class_metadata = @em.class_metadata entity.class

      # TODO: Handle associations
    end

    strongly_connected_components.find_strongly_connected_components

    # Now do the actual topological sorting to find the delete order.
    @entity_deletions.each do |entity|
      class_metadata = @em.class_metadata entity.class

      # Get the entities representing the SCC
      entity_component = strongly_connected_components.node_representing_strongly_connected_component entity

      # When $entity is part of a non-trivial strongly connected component group
      # (a group containing not only those entities alone), make sure we process it _after_ the
      # entity representing the group.
      # The dependency direction implies that "$entity depends on $entityComponent
      # being deleted first". The topological sort will output the depended-upon nodes first.
      if entity_component != entity
        sort.add_edge entity, entity_component, false
      end

      # TODO: Handle associations
    end

    sort.sort
  end

  def persist(entity : AORM::Entity) : Nil
    visited = Set(AORM::Entity).new

    self.persist entity, visited
  end

  private def persist(entity : AORM::Entity, visited : Set(AORM::Entity)) : Nil
    return unless visited.add? entity

    class_metadata = @em.class_metadata entity.class

    # We assume NEW, so DETACHED entities result in an exception on flush (constraint violation).
    # If we would detect DETACHED here we would throw an exception anyway with the same
    # consequences (not recoverable/programming error), so just assuming NEW here
    # lets us avoid some database lookups for entities with natural identifiers.
    case self.entity_state(entity, :new)
    in .managed? then return # TODO: Handle change tracking
    in .new?     then self.persist_new class_metadata, entity
    in .removed? # Remanage the entity
      @entity_deletions.delete entity
      self.add_to_identity_map entity

      # TODO: Handle change tracking

      @entity_states[entity] = :managed
    in .detached? then raise "detached entity cannot be persisted"
    end

    self.cascade_persist entity, visited
  end

  def remove(entity : AORM::Entity) : Nil
    visited = Set(AORM::Entity).new

    self.remove entity, visited
  end

  private def remove(entity : AORM::Entity, visited : Set(AORM::Entity)) : Nil
    return unless visited.add? entity

    # Cascade first, because schedule_for_delete() removes the entity from the identity map, which
    # can cause problems when a lazy proxy has to be initialized for the cascade operation.
    self.cascade_remove entity, visited

    case self.entity_state entity
    in .new?, .removed? then return                                 # noop
    in .managed?        then self.schedule_for_delete entity        # TODO: Handle eventing (preRemove)
    in .detached?       then raise "Cannot removed detached entity" # TODO: Make this an actual exception
    end
  end

  # Re-loads *entity* from the database and applies the fresh row to its in-memory state, discarding any pending changes.
  # The entity must be in the MANAGED state.
  def refresh(entity : AORM::Entity, lock_mode : AORM::LockMode? = nil) : Nil
    # TODO: Handle pessimistic locking
    state = self.entity_state entity
    raise "Cannot refresh entity that is not managed" unless state.managed?

    class_metadata = @em.class_metadata entity.class
    id = self.entity_identifier(entity).transform_values &.value

    # The persister routes through `create_entity`; the refresh hint signals
    # that an existing identity-map entry should be updated rather than
    # short-circuited.
    hints = AORM::Query::Hints.new refresh: true
    self.entity_persister(entity.class).load id, entity, nil, hints
  end

  # Schedules a collection for deletion (all rows in join table).
  def schedule_collection_deletion(collection : AORM::PersistentCollection(AORM::Entity)) : Nil
    @collection_deletions << collection
  end

  # Schedules a collection for update (insert/delete diff).
  def schedule_collection_update(collection : AORM::PersistentCollection(AORM::Entity)) : Nil
    @collection_updates << collection
  end

  # Removes a removed entity from all collections it belongs to.
  # Iterates through all managed entities to find collections containing the removed entity.
  private def cascade_remove(entity : AORM::Entity, visited : Set(AORM::Entity)) : Nil
    class_metadata = @em.class_metadata entity.class

    association_mappings = class_metadata.association_mappings.select { |_, v| v.cascade_remove? }

    unless association_mappings.empty?
      self.initialize_object entity
    end

    entities_to_cascade = [] of AORM::Entity

    association_mappings.each_value do |assoc|
      related_entities = class_metadata.field_info[assoc.field_name].get_value entity

      case related_entities
      when AORM::Collection, Enumerable(AORM::Entity)
        related_entities.each do |related_entity|
          entities_to_cascade << related_entity
        end
      when AORM::Entity
        entities_to_cascade << related_entities
      end
    end

    entities_to_cascade.each do |related_entity|
      self.remove related_entity, visited
    end
  end

  def initialize_object(entity : AORM::Entity) : Nil
    # TODO: initialize `Ghost` type?
  end

  def initialize_object(entity : AORM::PersistentCollection) : Nil
    # TODO: Initialize Collection?
  end

  protected def collection_persister(assoc : Mapping::Association)
    role = assoc.type

    if persister = @collection_persisters[role]?
      return persister
    end

    persister = case role
                when "many_to_many" then AORM::Persisters::Collection::ManyToManyPersister.new @em
                else
                  raise "Unsupported collection persister role #{role}."
                end

    # TODO: Handle caching?

    @collection_persisters[role] = persister
  end

  private def persist_new(class_metadata : AORM::Mapping::ClassInterface, entity : AORM::Entity) : Nil
    # TODO: Handle eventing

    id_generator = class_metadata.id_generator

    unless id_generator.post_insert?
      id_value = id_generator.generate @em, entity

      unless id_generator.is_a? ID::AssignedGenerator
        id_key = class_metadata.single_identifier_field_name
        id_value = {id_key => class_metadata.field_info[id_key].create_column_value id_value}

        class_metadata.set_identifier_values entity, id_value
      end

      # Some identifiers may be foreign keys to new entities.
      # In this case, we don't have the value yet and should treat it as if we have a post-insert generator
      #
      # TODO: Can we just ignore non-hash IDs?
      if !self.has_missing_ids_which_are_foreign_keys?(class_metadata, id_value) && id_value.is_a?(Hash)
        result = id_value.transform_values { |v, k| class_metadata.field_info[k].create_column_value v }
        @entity_identifiers[entity] = result
      end
    end

    @entity_states[entity] = :managed

    unless @entity_insertions.includes? entity
      self.schedule_for_insert entity
    end
  end

  private def cascade_persist(entity : AORM::Entity, visited : Set(AORM::Entity)) : Nil
    # TODO: Need to know how to skip uninitialized objects?
    # Maybe when we introduce `Ghost`

    class_metadata = @em.class_metadata entity.class

    class_metadata.association_mappings.select { |_, v| v.cascade_persist? }.each_value do |assoc|
      related_entities = class_metadata.field_info[assoc.field_name].get_value entity

      if related_entities.is_a? PersistentCollection
        related_entities = related_entities.unwrap
      end

      if related_entities.is_a?(AORM::Collection) || related_entities.is_a?(Enumerable(AORM::Entity))
        unless assoc.is_a? Mapping::ToMany
          raise "invalid association"
        end

        related_entities.each do |related_entity|
          self.persist related_entity, visited
        end
      elsif !related_entities.nil?
        if related_entities.is_a? AORM::Entity
          self.persist related_entities, visited
        else
          raise "BUG: invalid association"
        end
      end
    end
  end

  private def schedule_for_insert(entity : AORM::Entity) : Nil
    # TODO: Use proper exception classes for these
    raise "Dirty entity cannot be scheduled for insertion" if @entity_updates.includes? entity
    raise "Entity scheduled for deletion" if @entity_deletions.includes? entity
    raise "scheduled insert for managed entity" if @original_entity_data.has_key?(entity) && !@entity_insertions.includes?(entity)
    raise "Entity already scheduled for insertion" unless @entity_insertions.add? entity

    @entity_insertions << entity

    if @entity_identifiers.has_key? entity
      self.add_to_identity_map entity
    end
  end

  def is_scheduled_for_insert?(entity : AORM::Entity) : Bool
    @entity_insertions.includes? entity
  end

  # :nodoc:
  def schedule_for_delete(entity : AORM::Entity) : Nil
    if @entity_insertions.includes? entity
      if self.is_in_identity_map entity
        self.remove_from_identity_map entity
      end

      @entity_insertions.delete entity
      @entity_states.delete entity

      return
    end

    return unless self.is_in_identity_map entity

    self.remove_from_identity_map entity

    @entity_updates.delete entity

    unless @entity_deletions.includes? entity
      @entity_deletions << entity
      @entity_states[entity] = :removed
    end
  end

  def is_scheduled_for_delete?(entity : AORM::Entity) : Bool
    @entity_deletions.includes? entity
  end

  def schedule_for_update(entity : AORM::Entity) : Nil
    # TODO: Use proper exception classes for these
    raise "Entity has no identity" unless @entity_identifiers.has_key? entity
    raise "Entity scheduled for deletion" if @entity_deletions.includes? entity

    if !@entity_updates.includes?(entity) && !@entity_insertions.includes?(entity)
      @entity_updates << entity
    end
  end

  def is_scheduled_for_update?(entity : AORM::Entity) : Bool
    @entity_updates.includes? entity
  end

  def clear : Nil
    @identity_map.clear
    @entity_identifiers.clear
    @entity_states.clear
    @entity_deletions.clear
    @entity_insertions.clear
    @entity_persisters.clear
    @non_cascaded_new_detected_entities.clear
    @collection_deletions.clear
    @collection_updates.clear
    @extra_updates.clear
    @visited_collections.clear
    @pending_collection_element_removals.clear
  end

  def single_identifier_value(entity : AORM::Entity)
    class_metadata = @em.class_metadata entity.class

    if class_metadata.is_identifier_composite
      raise "illegal composite identifier"
    end

    values = self.is_in_identity_map(entity) ? self.entity_identifier(entity) : class_metadata.identifier_values(entity)

    id = values[class_metadata.identifier.first]?
    return nil if id.nil?

    raw_id = id.is_a?(Mapping::Value) ? id.value : id

    # Identifiers should always be DB-compatible primitive types
    unless raw_id.is_a?(DB::Any)
      raise "BUG: invalid entity identifier value"
    end

    raw_id
  end

  def entity_state(entity : AORM::Entity, assume : EntityState? = nil) : EntityState
    if state = @entity_states[entity]?
      return state
    end

    return assume if assume

    # State can only be NEW or DETACHED, because MANAGED/REMOVED states are known.
    # Note that you can not remember the NEW or DETACHED state in _entityStates since
    # the UoW does not hold references to such objects and the object hash can be reused.
    # More generally because the state may "change" between NEW/DETACHED without the UoW being aware of it.
    class_metadata = @em.class_metadata entity.class
    id = class_metadata.identifier_values entity

    if id.empty?
      return EntityState::New
    end

    if class_metadata.contains_foreign_identifier || class_metadata.contains_enum_identifier
      id = self.identifier_flattener.flatten_identifier class_metadata, id
    end

    if class_metadata.identifier_natural?
      # TODO: Handle versioning

      # Last try before DB lookup; check identity map
      self.try_get_by_id id, class_metadata.entity_class do
        return EntityState::Detached
      end

      # Lookup via DB
      if self.entity_persister(class_metadata.entity_class).exists(entity)
        return EntityState::Detached
      end

      return EntityState::New
    elsif !class_metadata.id_generator.post_insert?
      # if we have a pre insert generator we can't be sure that having an id
      # really means that the entity exists. We have to verify this through
      # the last resort: a db lookup

      # Last try before DB lookup; check identity map
      self.try_get_by_id id, class_metadata.entity_class do
        return EntityState::Detached
      end

      # Lookup via DB
      if self.entity_persister(class_metadata.entity_class).exists(entity)
        return EntityState::Detached
      end

      return EntityState::New
    end

    raise NotImplementedError.new "Unhandleable state"
  end

  def change_set(entity : AORM::Entity) : Hash(String, Change)
    unless @entity_change_sets.has_key? entity
      return Hash(String, Change).new
    end

    @entity_change_sets[entity]
  end

  def entity_identifier(entity : AORM::Entity) : Hash(String, AORM::Mapping::Value)
    @entity_identifiers[entity]? || raise "Unable to find \"#{entity.class.name}\" entity identifier associated with the UnitOfWork"
  end

  protected def entity_persister(entity_class : AORM::Entity.class) : AORM::Persisters::Entity::Interface
    if persister = @entity_persisters[entity_class]?
      return persister
    end

    class_metadata = @em.class_metadata entity_class

    # TODO: Support other types of persisters
    persister = case class_metadata.inheritance_type
                when .none? then AORM::Persisters::Entity::Basic.new @em, class_metadata
                else
                  raise "No persister found"
                end

    # TODO: Handle caching?

    @entity_persisters[entity_class] = persister
  end

  # :nodoc:
  def get_by_id_hash(id_hash : String, entity_class : AORM::Entity.class) : AORM::Entity?
    @identity_map[entity_class]?.try &.[id_hash]?
  end

  # :nodoc:
  def try_get_by_id(id : Hash(String, _), entity_class : AORM::Entity.class, &) : Nil
    id_hash = self.class.id_hash_by_identifier(id)

    if (klass = @identity_map[entity_class]?) && (entity = klass[id_hash]?)
      yield entity
    end
  end

  def add_to_identity_map(entity : AORM::Entity) : Bool
    class_metadata = @em.class_metadata entity.class
    id_hash = self.id_hash_of_entity entity
    entity_class = class_metadata.entity_class

    if @identity_map.has_key?(entity_class) && @identity_map[entity_class].has_key?(id_hash)
      if @identity_map[entity_class][id_hash] != entity
        raise "entity identity collision"
      end

      return false
    end

    (@identity_map[entity_class] ||= Hash(String, AORM::Entity).new)[id_hash] = entity

    true
  end

  def id_hash_of_entity(entity : AORM::Entity) : String
    identifier = @entity_identifiers[entity]?

    if !identifier || identifier.empty? || identifier.values.any?(&.value.nil?)
      raise "entity without identity"
    end

    self.class.id_hash_by_identifier identifier
  end

  def is_in_identity_map(entity : AORM::Entity) : Bool
    return false if !@entity_identifiers.has_key?(entity) || @entity_identifiers[entity].empty?

    class_metadata = @em.class_metadata entity.class
    id_hash = self.id_hash_of_entity entity

    # p({
    #   entity:          entity,
    #   in_identity_map: @identity_map.has_key?(class_metadata.entity_class) && @identity_map[class_metadata.entity_class].has_key?(id_hash),
    #   identity_map:    @identity_map,
    #   id_hash:         id_hash,
    #   entity_class:    class_metadata.entity_class,
    # })

    @identity_map.has_key?(class_metadata.entity_class) && @identity_map[class_metadata.entity_class].has_key?(id_hash)
  end

  def remove_from_identity_map(entity : AORM::Entity) : Bool
    class_metadata = @em.class_metadata entity.class
    id_hash = self.id_hash_of_entity entity

    # TODO: Use proper exception type
    raise "Entity has no identity" if id_hash.empty?

    if (identity = @identity_map[class_metadata.entity_class]?) && identity.has_key?(id_hash)
      identity.delete id_hash

      return true
    end

    false
  end

  def entity_changeset(entity : AORM::Entity) : Hash
    unless cs = @entity_change_sets[entity]?
      return {} of String => NoReturn
    end

    cs
  end

  # Schedules a follow-up UPDATE to apply the given changeset to *entity*. Used
  # by persisters when a FK can't be written at INSERT time because the
  # referenced entity hasn't been inserted yet (cyclic dependency). Multiple
  # extra updates for the same entity are merged.
  def schedule_extra_update(entity : AORM::Entity, changeset : Hash(String, Change)) : Nil
    if existing = @extra_updates[entity]?
      @extra_updates[entity] = existing.merge changeset
    else
      @extra_updates[entity] = changeset
    end
  end

  def extra_update_for(entity : AORM::Entity) : Hash(String, Change)
    @extra_updates[entity]? || Hash(String, Change).new
  end

  private def execute_extra_updates : Nil
    @extra_updates.each do |entity, changeset|
      # Swap the entity's main changeset out for the extra one so the persister's
      # update path writes only the patched columns.
      @entity_change_sets[entity] = changeset
      self.entity_persister(entity.class).update entity
    end

    @extra_updates.clear
  end

  def compute_changesets : Nil
    self.compute_scheduled_inserts_change_sets

    @identity_map.each do |entity_class, entity_hash|
      class_metadata = @em.class_metadata entity_class

      next if class_metadata.read_only?

      # TODO: Handle change tracking policies

      entity_hash.each_value do |entity|
        # Only MANAGED entities that are NOT SCHEDULED FOR INSERTION OR DELETION are processed here.
        if !@entity_insertions.includes?(entity) && !@entity_deletions.includes?(entity) && @entity_states.has_key?(entity)
          self.compute_change_set class_metadata, entity
        end
      end
    end
  end

  private def compute_scheduled_inserts_change_sets : Nil
    @entity_insertions.each do |entity|
      class_metadata = @em.class_metadata entity.class

      self.compute_change_set class_metadata, entity
    end
  end

  private def compute_change_set(class_metadata : AORM::Mapping::ClassInterface, entity : AORM::Entity) : Nil
    # TODO: Handle readonly objects

    unless class_metadata.inheritance_type.none?
      class_metadata = @em.class_metadata entity.class
    end

    actual_data = Hash(String, Mapping::Value).new

    # TODO: Invoke listeners
    class_metadata.field_info.each do |name, prop|
      if (assoc = class_metadata.association_mappings[name]?) && assoc.is_a?(Mapping::ToMany)
        # Promote a user-assigned ArrayCollection (or a PersistentCollection owned by another entity) into a PersistentCollection owned by this entity.
        next if prop.get_value(entity).nil?

        target_metadata = @em.class_metadata assoc.target_entity
        p_coll = prop.promote_collection entity, @em, target_metadata, assoc
        actual_data[name] = prop.create_column_value p_coll
        next
      end

      # TODO: Handle versioning
      if (!class_metadata.is_identifier(name) || !class_metadata.identifier_identity?) && true
        actual_data[name] = prop.create_column_value entity
      end
    end

    if original_data = @original_entity_data[entity]?
      change_set = Hash(String, Change).new

      actual_data.each do |prop_name, actual_value|
        # Skip partially omitted fields
        next unless original_data.has_key? prop_name

        original_value = original_data[prop_name].value
        actual_inner = actual_value.value

        # TODO: Handle enum types

        next if original_value == actual_inner

        # Regular field
        unless assoc = class_metadata.association_mappings[prop_name]?
          change_set[prop_name] = class_metadata.field_info[prop_name].create_change original_value, actual_inner

          next
        end

        if actual_inner.is_a? AORM::PersistentCollection
          raise "BUG: Not ToMany assoc" unless assoc.is_a? Mapping::ToMany
          owner = actual_inner.owner

          if owner.nil?
            actual_inner.set_owner entity, assoc
          elsif owner != entity
            # Force lazy load before cloning so the new owner doesn't share backing state with the original
            actual_inner.initialize_collection

            new_value = actual_inner.clone
            new_value.set_owner entity, assoc
            class_metadata.field_info[assoc.field_name].set_value entity, new_value
          end
        end

        if original_value.is_a? AORM::PersistentCollection
          unless @collection_deletions.includes? original_value
            @collection_deletions << original_value
          end

          next
        end

        if assoc.is_a? Mapping::ToOne
          if assoc.is_a? Mapping::OwningSide
            change_set[prop_name] = class_metadata.field_info[prop_name].create_change original_value, actual_inner
          end

          if original_value.is_a?(AORM::Entity) && assoc.orphan_removal?
            self.schedule_orphan_removal original_value
          end
        end
      end

      unless change_set.empty?
        @entity_change_sets[entity] = change_set
        @original_entity_data[entity] = actual_data.transform_values { |v, k| class_metadata.field_info[k].create_column_value v }
        @entity_updates << entity
      end
    else
      # Entity is NEW or MANAGED but not yet fully persisted (only has an id).
      # These result in an INSERT

      @original_entity_data[entity] = actual_data.transform_values { |v, k| class_metadata.field_info[k].create_column_value v }
      change_set = Hash(String, Change).new

      actual_data.each do |prop_name, actual_value|
        unless assoc = class_metadata.association_mappings[prop_name]?
          change_set[prop_name] = class_metadata.field_info[prop_name].create_change nil, actual_value.value

          next
        end

        if assoc.is_a? Mapping::ToOneOwningSide
          change_set[prop_name] = class_metadata.field_info[prop_name].create_change nil, actual_value.value
        end
      end

      @entity_change_sets[entity] = change_set
    end

    class_metadata.association_mappings.each do |field, assoc|
      value = class_metadata.field_info[field].get_value entity
      next if value.nil?

      self.compute_association_changes assoc, value

      if assoc.is_a?(Mapping::ManyToManyOwningSide) && value.is_a?(AORM::PersistentCollection) && value.dirty?
        @collection_updates << value
        @visited_collections << value
      end
    end
  end

  # Compute association changeset
  private def compute_association_changes(assoc : AORM::Mapping::Association, value) : Nil
    # TODO: Handle proxies

    unwrapped_value = if assoc.is_a?(Mapping::ToMany)
                        # Iterate the backing collection without forcing a lazy
                        # load — `unwrap` returns the inner ArrayCollection
                        # whether the PC is initialized or not. Uninitialized
                        # collections are simply empty.
                        if value.is_a?(AORM::PersistentCollection)
                          value.unwrap.to_a
                        else
                          raise "BUG: ToMany value is not iterable (#{value.class})"
                        end
                      elsif value.is_a?(AORM::Entity)
                        # ToOne: wrap single entity in array
                        [value]
                      else
                        raise "BUG: ToOne value is not an entity"
                      end

    target_class_metadata = @em.class_metadata assoc.target_entity

    unwrapped_value.each_with_index do |entity, idx|
      raise "BUG: unwrapped_value is not an entity" unless entity.is_a? AORM::Entity

      case self.entity_state(entity, EntityState::New)
      when .new?
        unless assoc.cascade_persist?
          # For now just record the details, because this may not be an issue if we later discover another pathway
          # through the object-graph where cascade-persistence is enabled for this object.
          @non_cascaded_new_detected_entities[entity] = {assoc, entity}
          next
        end

        self.persist_new target_class_metadata, entity
        self.compute_change_set target_class_metadata, entity
      when .removed?
        next unless assoc.is_a? Mapping::ToMany
        raise "BUG: value for ToMany assoc is not a collection" unless value.is_a? AORM::Collection

        @visited_collections << value

        # Defer the in-memory removal until after the transaction commits, so a
        # rollback leaves the collection's view of its elements unchanged.
        if value.is_a? AORM::PersistentCollectionInterface
          pending = @pending_collection_element_removals[value] ||= [] of AORM::Entity
          pending << entity
        end
      else
        # noop
      end
    end
  end

  def schedule_orphan_removal(entity : AORM::Entity) : Nil
    @orphan_removals.add entity
  end

  def trigger_eager_loads : Nil
    # TODO: Implement this
  end

  # Creates or retrieves an entity from hydrated data, returning the
  # identity-mapped instance when one already exists for this id_hash.
  def create_entity(
    entity_class : AORM::Entity.class,
    data : Hash,
    hints : AORM::Query::Hints = AORM::Query::Hints.new,
  ) : AORM::Entity
    class_metadata = @em.class_metadata entity_class

    id = identifier_flattener.flatten_identifier(class_metadata, data)
    id_hash = self.class.id_hash_by_identifier id

    # Check identity map for existing entity
    if (class_map = @identity_map[class_metadata.entity_class]?) && (entity = class_map[id_hash]?)
      # TODO: Know if entity is uninitialized?

      if hints.refresh?
        # Re-apply scalar fields from the freshly fetched row data and reset
        # the changeset baseline so the EM no longer sees pending changes.
        class_metadata.apply_data entity, data
        @original_entity_data[entity] = data.transform_values do |v, k|
          class_metadata.field_info[k].create_column_value(v).as Mapping::Value
        end
        @entity_change_sets.delete entity
        @entity_updates.delete entity
      end

      return entity
    end

    # This also handles setting ivars based on the data
    entity = class_metadata.new_instance(data)
    self.register_managed(entity, id, data)
    # TODO: Handle readonly hints

    # TODO: Handle eager loading entities

    # Initialize collections with owner and association metadata so they can lazy-load.
    class_metadata.association_mappings.each do |field_name, assoc|
      # TODO: Handle fetchAlias/fetchMode hints

      target_class_metadata = @em.class_metadata assoc.target_entity

      if assoc.is_a? Mapping::ToOne
        self.handle_to_one_during_hydration(class_metadata, entity, field_name, assoc, data)
      else
        raise "BUG: Assoc is not ToMany" unless assoc.is_a? Mapping::ToMany

        # TODO: Handle PersistentCollection in `data`

        # Do this here so `T` can be properly resolved
        # pp entity.class, target_class_metadata.class, assoc.class
        # pp class_metadata.field_info[field_name]
        fi = class_metadata.field_info[field_name]
        p_coll = fi.inject_collection entity, @em, target_class_metadata, assoc

        # TODO: Handle eager fetching hints

        @original_entity_data[entity][field_name] = fi.create_column_value p_coll
      end
    end

    # TODO: Handle deferring postLoad event

    entity
  end

  # Registers an entity as managed in the UnitOfWork.
  def register_managed(entity : AORM::Entity, id : Hash(String, _), data : Hash(String, _)) : Nil
    class_metadata = @em.class_metadata(entity.class)

    @entity_identifiers[entity] = id.transform_values { |v, k| class_metadata.field_info[k].create_column_value(v).as Mapping::Value }
    @entity_states[entity] = :managed

    # `data` may contain meta-mapping entries (FK column names) that don't correspond to entity fields — only persist values keyed by something the entity actually has an ivar for.
    typed_data = Hash(String, Mapping::Value).new
    data.each do |k, v|
      next unless class_metadata.field_info.has_key? k
      typed_data[k] = class_metadata.field_info[k].create_column_value(v).as Mapping::Value
    end
    @original_entity_data[entity] = typed_data

    self.add_to_identity_map(entity)
  end

  # Resolves a ToOne association during `create_entity`.
  # For owning side, reads the FK from the row data; identity-map hits resolve immediately, misses are queued for the hydrator's `cleanup` to avoid running a nested query while the main cursor is still active.
  # Inverse side is always queued.
  private def handle_to_one_during_hydration(
    class_metadata : Mapping::ClassInterface,
    entity : AORM::Entity,
    field_name : String,
    assoc : Mapping::ToOne,
    data : Hash,
  ) : Nil
    if assoc.is_a?(Mapping::ToOneOwningSide)
      target_class_metadata = @em.class_metadata assoc.target_entity
      associated_id = self.build_associated_id_from_row_data assoc, target_class_metadata, data

      if associated_id.nil?
        # FK is null. Property's default value (typed `Target?`) is already nil;
        # record that in original_entity_data so change tracking sees it.
        fi = class_metadata.field_info[field_name]
        @original_entity_data[entity][field_name] = fi.create_column_value entity
        return
      end

      # Identity-map hit: resolve inline — no query needed.
      related_id_hash = self.class.id_hash_by_identifier associated_id
      if (target_map = @identity_map[target_class_metadata.entity_class]?) && (existing = target_map[related_id_hash]?)
        self.assign_to_one_target class_metadata, entity, field_name, assoc, existing
        return
      end

      # Miss: defer to hydrator cleanup.
      db_id = associated_id.transform_values do |v|
        raw = v.is_a?(Mapping::Value) ? v.value : v
        raise "BUG: associated id value is not DB-compatible: #{raw.inspect}" unless raw.is_a?(DB::Any)
        raw.as(DB::Any)
      end
      @pending_to_one_resolutions << PendingToOneResolution.new(entity, field_name, assoc.target_entity, db_id)
    else
      # Inverse side: always eager via persister. Defer the SELECT to cleanup.
      raise "BUG: ToOne assoc is neither owning nor inverse side" unless assoc.is_a?(Mapping::InverseSide)
      @pending_to_one_resolutions << PendingToOneResolution.new(entity, field_name, assoc.target_entity, nil)
    end
  end

  # Reads FK column values out of *data* (keyed by the FK column name, the way
  # the hydrator's meta-mapping branch deposited them) and returns the target's
  # identifier hash, or nil if any column is null (treat the entire FK as null).
  private def build_associated_id_from_row_data(
    assoc : Mapping::ToOneOwningSide,
    target_class_metadata : Mapping::ClassInterface,
    data : Hash,
  ) : Hash(String, DB::Any)?
    associated_id = Hash(String, DB::Any).new

    assoc.target_to_source_key_columns.each do |target_column, source_column|
      value = data[source_column]?
      raw = value.is_a?(Mapping::Value) ? value.value : value

      if raw.nil?
        # If any FK column is null, treat the whole reference as null.
        return nil
      end

      target_field_name = target_class_metadata.field_names[target_column]?
      raise "BUG: Target column '#{target_column}' not mapped on #{target_class_metadata.entity_class}" unless target_field_name

      raise "BUG: associated id value is not DB-compatible: #{raw.inspect}" unless raw.is_a?(DB::Any)
      associated_id[target_field_name] = raw.as(DB::Any)
    end

    associated_id.empty? ? nil : associated_id
  end

  # Walks any ToOne resolutions queued during hydration and writes the loaded target onto its source entity.
  # Called by the hydrator's `cleanup` once the main result-set cursor has closed.
  def resolve_pending_to_one_associations : Nil
    return if @pending_to_one_resolutions.empty?

    pending = @pending_to_one_resolutions
    @pending_to_one_resolutions = [] of PendingToOneResolution

    pending.each do |resolution|
      source = resolution.source
      source_class_metadata = @em.class_metadata source.class
      assoc = source_class_metadata.association_mappings[resolution.field_name]
      raise "BUG: pending resolution references non-ToOne association" unless assoc.is_a?(Mapping::ToOne)

      target = if id = resolution.target_id
                 # An earlier resolution in this batch may have already loaded
                 # the same target — re-check the identity map before issuing a
                 # SELECT.
                 existing : AORM::Entity? = nil
                 self.try_get_by_id(id, resolution.target_class) { |e| existing = e }
                 existing || self.entity_persister(resolution.target_class).load(id)
               else
                 raise "BUG: inverse-side pending resolution but assoc isn't InverseSide" unless assoc.is_a?(Mapping::InverseSide)
                 self.entity_persister(assoc.target_entity).load_one_to_one_entity assoc, source
               end

      next if target.nil?

      self.assign_to_one_target source_class_metadata, source, resolution.field_name, assoc, target
    end
  end

  # Writes a resolved ToOne target entity onto its source via the macro-driven
  # `apply_data` (so the dispatch lands on the right ivar type), updates the
  # original-data baseline for change tracking, and applies the OneToOne
  # `inversed_by` back-pointer when relevant.
  private def assign_to_one_target(
    source_class_metadata : Mapping::ClassInterface,
    source : AORM::Entity,
    field_name : String,
    assoc : Mapping::Association,
    target : AORM::Entity,
  ) : Nil
    source_class_metadata.apply_data source, {field_name => target}

    fi = source_class_metadata.field_info[field_name]
    @original_entity_data[source][field_name] = fi.create_column_value source

    # OneToOne owning-side: reflect the bidirectional link on the inverse end.
    return unless assoc.is_a?(Mapping::OneToOneOwningSide)
    inversed_by = assoc.inversed_by
    return unless inversed_by

    target_class_metadata = @em.class_metadata target.class
    return unless target_class_metadata.field_info.has_key? inversed_by

    target_class_metadata.apply_data target, {inversed_by => source}
  end

  def load_collection(collection : AORM::PersistentCollection) : Nil
    assoc = collection.association
    persister = self.entity_persister(assoc.target_entity)

    # The persister hydrates straight into the collection via the `:collection`
    # hydrator hint, so there's nothing to re-add here.
    case assoc
    when Mapping::ManyToMany
      persister.load_many_to_many_collection(assoc, collection.owner.not_nil!, collection)
    when Mapping::OneToMany
      persister.load_one_to_many_collection(assoc, collection.owner.not_nil!, collection)
    end

    collection.initialized = true
  end

  private def try_get(id : Hash(String, Mapping::Value), entity_class : AORM::Entity.class, & : AORM::Entity ->) : Nil
    class_metadata = @em.class_metadata(entity_class)
    id_hash = identifier_flattener.flatten_identifier(class_metadata, id)

    if (klass = @identity_map[entity_class]?) && (entity = klass[id_hash]?)
      yield entity
    end
  end

  private def has_missing_ids_which_are_foreign_keys?(class_metadata : Mapping::ClassInterface, id : Hash(String, _)) : Bool
    id.any? do |id_field, id_field_value|
      value = id_field_value.is_a?(Mapping::Value) ? id_field_value.value : id_field_value

      value.nil? && class_metadata.association_mappings.has_key? id_field
    end
  end

  private def has_missing_ids_which_are_foreign_keys?(class_metadata : Mapping::ClassInterface, id : _) : Bool
    false
  end

  private def index_identifiers_by_name(id_arr : Array(Mapping::Value)) : Hash(String, Mapping::Value)
    id_arr.each_with_object(Hash(String, Mapping::Value).new) do |id, id_hash|
      id_hash[id.name] = id
    end
  end
end
