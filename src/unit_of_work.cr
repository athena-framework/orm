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
        entity_matadata = em.class_metadata entity.class

        if current_metadata.try(&.entity_class) != entity_matadata.entity_class || (!entity_matadata.id_generator.is_a?(ID::AssignedGenerator))
          current_metadata = entity_matadata
          batches << new(entity_matadata, [entity])
          batch_index += 1

          next
        end

        batches[batch_index].entities << entity
      end

      batches
    end
  end

  def self.id_hash_by_identifier(identifier : Hash(String | Number, _)) : String
    identifier.each do |k, v|
      if v.is_a?(::Enum)
        identifier[k] = v.value
      end
    end

    identifier.each_value.join ' '
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

  @original_entity_data = Hash(AORM::Entity, Hash(String, Mapping::Value)).new do |hash, key|
    hash[key] = Hash(String, Mapping::Value).new
  end.compare_by_identity
  @entity_change_sets = Hash(AORM::Entity, Hash(String, Change)).new.compare_by_identity
  @orphan_removals = Set(AORM::Entity).new.compare_by_identity

  @non_cascaded_new_detected_entities = Hash(AORM::Entity, Tuple(AORM::Mapping::Association, AORM::Entity)).new.compare_by_identity

  getter identifier_flattener : AORM::Utility::IdentifierFlattener { AORM::Utility::IdentifierFlattener.new(self, @em.metadata_factory) }

  def initialize(@em : AORM::EntityManagerInterface)
  end

  def commit : Nil
    # TODO: Ensure connected to primary

    # TODO: Handle eventing (preFlush)

    self.compute_changesets

    # Nothing to do
    # TODO: Handle collection updates/deletions
    if @entity_deletions.empty? && @entity_insertions.empty? && @entity_updates.empty? && @orphan_removals.empty?
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
      # TODO: Handle collection deletions

      @entity_insertions.each do |entity|
        # Perform entity insertions first, so that all new entities have their rows in the database
        # and can be referred to by foreign keys. The commit order only needs to take new entities
        # into account (new entities referring to other new entities), since all other types (entities
        # with updates or scheduled deletions) are currently not a problem, since they are already
        # in the database.
        self.execute_inserts @em.class_metadata entity.class
      end

      # @entity_updates.each do |entity|
      #   self.execute_updates @em.class_metadata entity.class
      # end

      # @entity_deletions.each do |entity|
      #   self.execute_deletions @em.class_metadata entity.class
      # end
    rescue ex : ::Exception
      @em.close
      # TODO: Handle cache persisters

      raise ex
    end

    # TODO: Handle cache persisters
    # TODO: Take snapshots of collections

    # TODO: Handle eventing (postFlush)

    self.post_commit_cleanup
  end

  def scheduled_entity_insertions : Set(AORM::Entity)
    @entity_insertions
  end

  private def assert_that_there_are_no_unintentionally_non_persisted_associations : Nil
    # @non_cascaded_new_detected_entities contains entities discovered via association
    # traversal that were NEW at the time. If cascade were enabled, these would be
    # auto-persisted. Without cascade, we should error if they weren't explicitly persisted.
    #
    # For now, since cascade isn't implemented, we allow all explicitly persisted entities.
    # TODO: Implement cascade and properly validate non-cascaded associations
    @non_cascaded_new_detected_entities.clear
  end

  private def post_commit_cleanup : Nil
    @entity_insertions.clear
    @entity_updates.clear
    @entity_deletions.clear
    @entity_change_sets.clear
    @orphan_removals.clear
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

  private def compute_insert_execution_order : Array(AORM::Entity)
    sort = Internal::TopologicalSort.new

    # Ensure all nodes are added
    @entity_insertions.each do |entity|
      sort.add_node entity
    end

    # Add edges
    @entity_insertions.each do |entity|
      class_metadata = @em.class_metadata entity.class

      # TODO: Handle associations
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

  private def execute_updates(class_metadata : AORM::Mapping::ClassBase) : Nil
    entity_class = class_metadata.entity_class
    persister = self.entity_persister class_metadata.entity_class

    @entity_updates.each do |entity|
      next if entity_class != @em.class_metadata(entity.class).entity_class

      # TODO: Handle eventing (preUpdate)

      unless @entity_change_sets[entity].empty?
        persister.update entity
      end

      @entity_updates.delete entity

      # TODO: Handle eventing (postUpdate)
    end
  end

  private def execute_deletions(class_metadata : AORM::Mapping::ClassBase) : Nil
    entity_class = class_metadata.entity_class
    persister = self.entity_persister class_metadata.entity_class

    @entity_deletions.each do |entity|
      next if entity_class != @em.class_metadata(entity.class).entity_class

      persister.delete entity

      @entity_deletions.delete entity
      @entity_identifiers.delete entity
      @entity_states.delete entity
      @original_entity_data.delete entity

      unless class_metadata.is_identifier_composite?
        property = class_metadata.property(class_metadata.single_identifier_field_name).not_nil!

        if property.is_a?(AORM::Mapping::FieldMetadata) && property.has_value_generator?
          property.set_value entity, nil
        end
      end

      # TODO: Handle eventing (postRemove)
    end
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

    # TODO: Handle cascade for nested entities
  end

  def remove(entity : AORM::Entity) : Nil
    visited = Set(AORM::Entity).new

    self.remove entity, visited
  end

  private def remove(entity : AORM::Entity, visited : Set(AORM::Entity)) : Nil
    return unless visited.add? entity

    # Cascade first, because schedule_for_delete() removes the entity from the identity map, which
    # can cause problems when a lazy proxy has to be initialized for the cascade operation.
    # TODO: Handle cascade for nested models

    case self.entity_state entity
    in .new?      then return                                 # noop
    in .removed?  then return                                 # noop
    in .managed?  then self.schedule_for_delete entity        # TODO: Handle eventing (preRemove)
    in .detached? then raise "Cannot removed detached entity" # TODO: Make this an actual exception
    end
  end

  private def persist_new(class_metadata : AORM::Mapping::ClassInterface, entity : AORM::Entity) : Nil
    # TODO: Handle eventing

    id_generator = class_metadata.id_generator

    unless id_generator.post_insert?
      id_value = id_generator.generate @em, entity

      # TODO: Handle non-post-insert generators
    end

    @entity_states[entity] = :managed

    unless @entity_insertions.includes? entity
      self.schedule_for_insert entity
    end
  end

  private def schedule_for_insert(entity : AORM::Entity) : Nil
    # TODO: Use proper exception classes for these
    raise "Entity scheduled for deletion" if @entity_deletions.includes? entity
    raise "Entity already scheduled for insertion" unless @entity_insertions.add? entity

    if @entity_identifiers.has_key? entity
      self.add_to_identity_map entity
    end
  end

  def is_scheduled_for_insert?(entity : AORM::Entity) : Bool
    @entity_insertions.includes? entity
  end

  private def schedule_for_delete(entity : AORM::Entity) : Nil
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

  def refresh(entity : AORM::Entity) : Nil
    visited = Set(UInt64).new

    self.remove entity, visited
  end

  private def refresh(entity : AORM::Entity, visited : Set(AORM::Entity)) : Nil
    return unless visited.add? entity

    class_metadata = @em.class_metadata entity.class

    # TODO: Use proper exception type for this
    raise "Entity not managed" if !self.entity_state(entity).managed?

    self.entity_persister.refresh

    # TODO: Handle cascade refreshing
  end

  def clear : Nil
    @identity_map.clear
    @entity_identifiers.clear
    @entity_states.clear
    @entity_deletions.clear
    @entity_insertions.clear
    @entity_persisters.clear
    @non_cascaded_new_detected_entities.clear
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
    @entity_identifiers[entity]? || raise "no identifier found"
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

  protected def try_get_by_id(id : Hash(String, _), entity_class : AORM::Entity.class, &) : Nil
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

    if !identifier || identifier.empty? || identifier.none?
      raise "entity without identity"
    end

    self.class.id_hash_by_identifier identifier
  end

  def is_in_identity_map(entity : AORM::Entity) : Bool
    return false if !@entity_identifiers.has_key?(entity) || @entity_identifiers[entity].empty?

    class_metadata = @em.class_metadata entity.class
    id_hash = self.id_hash_of_entity entity

    @identity_map.has_key?(class_metadata.entity_class) && @identity_map[class_metadata.entity_class].has_key?(id_hash)
  end

  def remove_from_identity_map(entity : AORM::Entity) : Bool
    class_metadata = @em.class_metadata entity.class
    id_hash = self.id_hash_of_entity entity

    # TODO: Use proper exception type
    raise "Entity has no identity" if id_hash.empty?

    return true if @identity_map.delete class_metadata.entity_class

    false
  end

  def entity_changeset(entity : AORM::Entity) : Hash
    unless cs = @entity_change_sets[entity]?
      return {} of String => NoReturn
    end

    cs
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

    # TODO: Invoke listeners
    actual_data = class_metadata.field_info.to_h do |name, prop|
      value = prop.get_value entity

      # TODO: Handle collection valued associations

      # TODO: Handle versioning
      if (!class_metadata.is_identifier(name) || !class_metadata.identifier_identity?) && true
        {name, value}
      else
        {name, nil}
      end
    end.compact!

    if original_data = @original_entity_data[entity]?
      change_set = Hash(String, Change).new

      actual_data.each do |prop_name, actual_value|
        # Skip partially omitted fields
        next unless original_data.has_key? prop_name

        original_value = original_data[prop_name].value

        # TODO: Handle enum types

        # Skip if value hasn't changed
        next if original_value == actual_value

        # Regular field
        unless class_metadata.association_mappings.has_key? prop_name
          change_set[prop_name] = class_metadata.field_info[prop_name].create_change original_value, actual_value

          next
        end

        # TODO: Handle collections and associations
      end

      unless change_set.empty?
        @entity_change_sets[entity] = change_set
        @original_entity_data[entity] = actual_data.transform_values { |v, k| class_metadata.field_info[k].create_column_value v }
        @entity_updates << entity
      end
    else
      # Entity is NEW or MANAGED but not yet fully persisted (only has an id).
      # These result in an INSERT

      # TODO: Implement this
    end

    # TODO: Handle changes in associated data
  end

  # Compute association changeset
  private def compute_change_set(property : AORM::Mapping::AssociationMetadata, value : AORM::Entity) : Nil
    # TODO: Handle proxies
    # TODO: Handle non ToOne associations
    unwrapped_value = [value]
    target_entity = property.target_entity
    target_class_metadata = @em.class_metadata target_entity

    unwrapped_value.each_with_index do |entity, idx|
      case self.entity_state(entity, EntityState::New)
      when .new?
        # TODO: Allow providing cascade option on column
        @non_cascaded_new_detected_entities[entity] = {property, entity}

        self.persist_new target_class_metadata, entity
        self.compute_change_set target_class_metadata, entity
      when .removed?
        # TODO: Handle non ToOne associations
      else
        # noop
      end
    end
  end

  def schedule_orphan_removal(entity : AORM::Entity) : Nil
    @orphan_removals.add entity
  end

  # Creates or retrieves an entity from hydrated data.
  # Mirrors Doctrine's UnitOfWork::createEntity.
  def create_entity(
    class_metadata : AORM::Mapping::ClassInterface,
    data : Hash(String, DB::Any?),
    hints : Hash(String, String) = {} of String => String,
  ) : AORM::Entity
    id = identifier_flattener.flatten_identifier(class_metadata, data)
    id_hash = self.class.id_hash_by_identifier id

    # Check identity map for existing entity
    if (class_map = @identity_map[class_metadata.entity_class]?) && (entity = class_map[id_hash]?)
      # TODO: Handle hints

      # TODO: Know if entity is uninitialized?

      # TODO: Handle hints

      return entity
    end

    entity = class_metadata.new_instance(data)
    # TODO: Handle hints
    self.register_managed(entity, id, data)

    entity
  end

  # Registers an entity as managed in the UnitOfWork.
  def register_managed(entity : AORM::Entity, id : Hash(String, _), data : Hash(String, _)) : Nil
    class_metadata = @em.class_metadata(entity.class)

    @entity_identifiers[entity] = id.transform_values { |v, k| class_metadata.field_info[k].create_column_value v }
    @entity_states[entity] = :managed
    @original_entity_data[entity] = data.transform_values { |v, k| class_metadata.field_info[k].create_column_value v }
    self.add_to_identity_map(entity)
  end

  private def try_get(id : Hash(String, AORM::Mapping::Value), entity_class : AORM::Entity.class, & : AORM::Entity ->) : Nil
    class_metadata = @em.class_metadata(entity_class)
    id_hash = identifier_flattener.flatten_identifier(class_metadata, id)

    if (klass = @identity_map[entity_class]?) && (entity = klass[id_hash]?)
      yield entity
    end
  end

  private def has_missing_ids_which_are_foreign_keys?(class_metadata : AORM::Mapping::ClassBase, id_arr : Array(AORM::Mapping::Value)) : Bool
    id_arr.any? { |value| value.value.nil? && class_metadata.property(value.name).is_a?(AORM::Mapping::AssociationMetadata) }
  end

  private def index_identifiers_by_name(id_arr : Array(AORM::Mapping::Value)) : Hash(String, AORM::Mapping::Value)
    id_arr.each_with_object(Hash(String, AORM::Mapping::Value).new) do |id, id_hash|
      id_hash[id.name] = id
    end
  end
end
