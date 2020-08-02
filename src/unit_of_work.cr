class Athena::ORM::UnitOfWork
  record Change, old : AORM::Mapping::Value?, new : AORM::Mapping::Value

  enum EntityState
    Managed
    New
    Detached
    Removed
  end

  @identity_map = Hash(AORM::Entity.class, Hash(String, AORM::Entity)).new

  @entity_identifiers = Hash(UInt64, Hash(String, AORM::Mapping::Value)).new

  @entity_states = Hash(UInt64, EntityState).new

  # Pending entity deltions
  @entity_deletions = Hash(UInt64, AORM::Entity).new

  # Pending entity insertions
  @entity_inserstions = Hash(UInt64, AORM::Entity).new

  # Pending entity updates
  @entity_updates = Hash(UInt64, AORM::Entity).new

  @entity_persisters = Hash(AORM::Entity.class, AORM::Persisters::Entity::Interface).new

  @original_entity_data = Hash(UInt64, Hash(String, AORM::Mapping::Value)).new
  @entity_change_sets = Hash(UInt64, Hash(String, Change)).new

  def initialize(@em : AORM::EntityManagerInterface); end

  def commit(entity : AORM::Entity? = nil) : Nil
    # TODO: Handle eventing (preFlush)

    self.compute_changesets

    # Nothing to do
    return if @entity_deletions.empty? && @entity_inserstions.empty? && @entity_updates.empty?

    # p! @entity_inserstions
    # p! @entity_updates
    # p! @entity_deletions

    # TODO: determine the order of the inserts
    # so that referential integrity is maintained.

    @em.transaction do
      @entity_inserstions.each_value do |entity|
        self.execute_inserts entity.class.entity_class_metadata
      end

      @entity_updates.each do |obj_id, entity|
        self.execute_updates entity.class.entity_class_metadata
      end

      @entity_deletions.each do |obj_id, entity|
        self.execute_deleteions entity.class.entity_class_metadata
      end
    rescue ex : ::Exception
      @em.close
      # TODO: Handle cache persisters

      raise ex
    end

    # TODO: Handle cache persisters
    # TOOD: Take snapshots of collections

    # TODO: Handle eventing (postFlush)

    self.post_commit_cleanup
  end

  private def post_commit_cleanup
    @entity_inserstions.clear
    @entity_updates.clear
    @entity_deletions.clear
    @entity_change_sets.clear
  end

  private def execute_inserts(class_metadata : AORM::Mapping::ClassBase) : Nil
    entity_class = class_metadata.entity_class
    persister = self.entity_persister class_metadata.entity_class
    generation_plan = class_metadata.value_generation_plan

    @entity_inserstions.each do |obj_id, entity|
      next if entity_class != entity.class.entity_class_metadata.entity_class

      persister.insert entity

      if generation_plan.contains_deferred?
        obj_id = entity.object_id
        id = persister.identifier entity

        @entity_identifiers[obj_id] = self.flatten_id id
        @entity_states[obj_id] = :managed

        id.each do |i|
          @original_entity_data[obj_id][i.name] = i
        end

        self.add_to_identity_map entity
      end

      @entity_inserstions.delete obj_id

      # TODO: Handle eventing (postPersist)
    end
  end

  private def execute_updates(class_metadata : AORM::Mapping::ClassBase) : Nil
    entity_class = class_metadata.entity_class
    persister = self.entity_persister class_metadata.entity_class

    @entity_updates.each do |obj_id, entity|
      next if entity_class != entity.class.entity_class_metadata.entity_class

      # TODO: Handle eventing (preUpdate)

      unless @entity_change_sets[obj_id].empty?
        persister.update entity
      end

      @entity_updates.delete obj_id

      # TODO: Handle eventing (postUpdate)
    end
  end

  private def execute_deleteions(class_metadata : AORM::Mapping::ClassBase) : Nil
    entity_class = class_metadata.entity_class
    persister = self.entity_persister class_metadata.entity_class

    @entity_deletions.each do |obj_id, entity|
      next if entity_class != entity.class.entity_class_metadata.entity_class

      persister.delete entity

      @entity_deletions.delete obj_id
      @entity_identifiers.delete obj_id
      @entity_states.delete obj_id
      @original_entity_data.delete obj_id

      unless class_metadata.is_identifier_composite?
        property = class_metadata.property(class_metadata.single_identifier_field_name).not_nil!

        if property.has_value_generator?
          property.set_value entity, nil
        end
      end

      # TODO: Handle eventing (postRemove)
    end
  end

  def persist(entity : AORM::Entity) : Nil
    visited = Set(UInt64).new

    self.persist entity, visited
  end

  private def persist(entity : AORM::Entity, visited : Set(UInt64)) : Nil
    obj_id = entity.object_id

    return unless visited.add? obj_id

    class_metadata = entity.class.entity_class_metadata

    case self.entity_state(entity, :new)
    in .managed? then return # TODO: Handle change tracking
    in .new?     then self.persist_new class_metadata, entity
    in .removed? # Remanage the entity
      @entity_deletions.delete obj_id
      self.add_to_identity_map entity

      @entity_states[obj_id] = :managed
    in .detached? then return # noop
    end

    # TODO: Handle cascade for nested entities
  end

  def remove(entity : AORM::Entity) : Nil
    visited = Set(UInt64).new

    self.remove entity, visited
  end

  private def remove(entity : AORM::Entity, visited : Set(UInt64)) : Nil
    obj_id = entity.object_id

    return unless visited.add? obj_id

    # TODO: Handle cascade for nested models

    case self.entity_state entity
    in .new?     then return                                  # noop
    in .removed? then return                                  # noop
    in .managed? then self.schedule_for_delete entity         # TODO: Handle eventing (preRemove)
    in .detached? then raise "Cannot removed detached entity" # TODO: Make this an actual exception
    end
  end

  private def persist_new(class_metadata : AORM::Mapping::ClassBase, entity : AORM::Entity) : Nil
    obj_id = entity.object_id

    generation_plan = class_metadata.value_generation_plan
    persister = self.entity_persister class_metadata.entity_class
    generation_plan.execute_immediate @em, entity

    unless generation_plan.contains_deferred?
      id = persister.identifier entity

      unless self.has_missing_ids_which_are_foreign_keys? class_metadata, id
        @entity_identifiers[obj_id] = self.flatten_id id
      end
    end

    @entity_states[obj_id] = :managed
    self.schedule_for_insert entity
  end

  private def schedule_for_insert(entity : AORM::Entity) : Nil
    obj_id = entity.object_id

    # TODO: Use proper exception classes for these
    raise "Entity scheduled for deletion" if @entity_deletions.has_key? obj_id
    raise "Entity already scheduled for insertion" if @entity_inserstions.has_key? obj_id

    @entity_inserstions[obj_id] = entity

    if @entity_identifiers.has_key? obj_id
      self.add_to_identity_map entity
    end
  end

  private def schedule_for_delete(entity : AORM::Entity) : Nil
    obj_id = entity.object_id

    if @entity_inserstions.has_key? obj_id
      @entity_inserstions.delete obj_id
      @entity_identifiers.delete obj_id
      @entity_states.delete obj_id

      return
    end

    return unless self.is_in_identity_map entity

    self.remove_from_identity_map entity

    @entity_updates.delete obj_id

    unless @entity_deletions.has_key? obj_id
      @entity_deletions[obj_id] = entity
      @entity_states[obj_id] = :removed
    end
  end

  def clear : Nil
    @identity_map.clear
    @entity_identifiers.clear
    @entity_states.clear
    @entity_deletions.clear
    @entity_inserstions.clear
    @entity_persisters.clear
  end

  def entity_state(entity : AORM::Entity, assume : EntityState? = nil) : EntityState
    obj_id = entity.object_id

    if state = @entity_states[obj_id]?
      return state
    end

    return assume if assume

    class_metadata = entity.class.entity_class_metadata
    persister = self.entity_persister class_metadata.entity_class
    id = persister.identifier entity

    return EntityState::New if id.empty?

    flat_id = self.flatten_id id

    # TODO: Handle AssociationMetadata
    if class_metadata.is_identifier_composite? || !class_metadata.property(class_metadata.single_identifier_field_name).not_nil!.has_value_generator?
      # TODO: Handle versioned fields

      self.try_get flat_id, class_metadata.root_class do
        return EntityState::Detached
      end

      # TODO: Handle DB lookups

      return EntityState::New
    end

    # TODO: Handle deferred value generation plans

    raise NotImplementedError.new "Unhandleable state"
  end

  def change_set(entity : AORM::Entity) : Hash(String, Change)
    obj_id = entity.object_id

    unless @entity_change_sets.has_key? obj_id
      return Hash(String, Change).new
    end

    @entity_change_sets[obj_id]
  end

  def entity_identifier(entity : AORM::Entity) : Hash(String, AORM::Mapping::Value)
    @entity_identifiers[entity.object_id]
  end

  protected def entity_persister(entity_class : AORM::Entity.class) : AORM::Persisters::Entity::Interface
    if persister = @entity_persisters[entity_class]?
      return persister
    end

    class_metadata = entity_class.entity_class_metadata

    persister = case class_metadata.inheritence_type
                in .none? then AORM::Persisters::Entity::Basic.new @em, class_metadata
                end

    # TODO: Handle cacheing

    @entity_persisters[entity_class] = persister
  end

  protected def try_get_by_id(id : Hash(String, Int | String), entity_class : AORM::Entity.class) : AORM::Entity?
    id_hash = id.values.join " "

    if (klass = @identity_map[entity_class]?) && (entity = klass[id_hash]?)
      yield entity
    end
  end

  def add_to_identity_map(entity : AORM::Entity) : Bool
    obj_id = entity.object_id

    class_metadata = entity.class.entity_class_metadata
    identifier = @entity_identifiers[obj_id]?

    if identifier.nil? || identifier.empty?
      # TODO: Use a property exception
      raise "Entity without an identifier"
    end

    id_hash = identifier.values.join " " { |v| v.value }
    class_name = class_metadata.root_class

    if @identity_map.has_key?(class_name) && @identity_map[class_name].has_key?(id_hash)
      return false
    end

    unless @identity_map.has_key? class_name
      @identity_map[class_name] = Hash(String, AORM::Entity).new
    end

    @identity_map[class_name][id_hash] = entity

    true
  end

  def is_in_identity_map(entity : AORM::Entity) : Bool
    obj_id = entity.object_id

    return false if !@entity_identifiers.has_key?(obj_id) || @entity_identifiers[obj_id].empty?

    class_metadata = entity.class.entity_class_metadata
    id_hash = @entity_identifiers[obj_id].values.join " "

    @identity_map.has_key?(class_metadata.root_class) && @identity_map[class_metadata.root_class].has_key?(id_hash)
  end

  def remove_from_identity_map(entity : AORM::Entity) : Bool
    obj_id = entity.object_id
    class_metadata = entity.class.entity_class_metadata
    id_hash = @entity_identifiers[obj_id].values.join " "

    # TODO: Use proper exception type
    raise "Entity has no identity" if id_hash.blank?

    class_name = class_metadata.root_class

    return true if @identity_map.has_key?(class_metadata.root_class) && @identity_map.has_key?(id_hash)

    false
  end

  private def compute_changesets : Nil
    self.compute_scheduled_inserts_change_sets

    @identity_map.each do |entity_class, entity_hash|
      class_metadata = entity_class.entity_class_metadata

      # TODO: Skip readonly classes
      # TODO: Handle change tracking policies

      entity_hash.each_value do |entity|
        # TODO: Skip ghosts/proxies
        obj_id = entity.object_id

        if !@entity_inserstions.has_key?(obj_id) && !@entity_deletions.has_key?(obj_id) && @entity_states.has_key?(obj_id)
          self.compute_change_set class_metadata, entity
        end
      end
    end
  end

  private def compute_scheduled_inserts_change_sets : Nil
    @entity_inserstions.each do |_, entity|
      class_metadata = entity.class.entity_class_metadata

      self.compute_change_set class_metadata, entity
    end
  end

  private def compute_change_set(class_metadata : AORM::Mapping::ClassBase, entity : AORM::Entity) : Nil
    obj_id = entity.object_id

    # TODO: Handle read only objects
    # TODO: Handle inheritence types
    # TODO: Handle eventing (preFlush) & ~ListenersInvoker::INVOKE_MANAGER???

    actual_data = Hash(String, AORM::Mapping::Value).new

    class_metadata.each do |property|
      column_value = property.get_value entity
      name = property.name

      if (
           !class_metadata.is_identifier?(name) ||
           # TODO: Handle non fieldMetadatas
           !class_metadata.property(name).not_nil!.has_value_generator? ||
           !class_metadata.property(name).not_nil!.value_generator.not_nil!.type.identity?
         ) # TODO: Handle versioned columns
        actual_data[name] = column_value
      end
    end

    if !@original_entity_data.has_key? obj_id
      # entity is new or managed but not fully persisted yet

      @original_entity_data[obj_id] = actual_data
      changeset = Hash(String, Change).new

      actual_data.each do |name, v|
        changeset[name] = Change.new nil, v
      end

      @entity_change_sets[obj_id] = changeset
    else
      # entity is fully managed
      original_data = @original_entity_data[obj_id]
      # TODO: Handle different change tracking policies
      changeset = Hash(String, Change).new

      actual_data.each do |name, actual_value|
        next if !original_data.has_key? name

        original_value = original_data[name]

        # Skip if value hasn't changed
        next if original_value.value == actual_value.value

        property = class_metadata.property(name).not_nil!

        # TODO: Handle collections

        case property
        when AORM::Mapping::Column
          # TODO: Handle notify change tracking policy
          changeset[name] = Change.new original_value, actual_value
          # TODO: Handle associations
        end

        unless changeset.empty?
          @entity_change_sets[obj_id] = changeset
          @original_entity_data[obj_id] = actual_data
          @entity_updates[obj_id] = entity
        end
      end

      # TODO: Look for changes in associations
    end
  end

  protected def manage_entity(entity : AORM::Entity) : AORM::Entity
    class_metadata = entity.class.entity_class_metadata
    persister = self.entity_persister class_metadata.entity_class
    obj_id = entity.object_id

    @entity_identifiers[obj_id] = flatten_id persister.identifier entity
    @entity_states[obj_id] = :managed
    self.compute_change_set class_metadata, entity

    self.add_to_identity_map entity

    entity
  end

  private def try_get(id : Hash(String, AORM::Mapping::Value), entity_class : AORM::Entity.class, & : AORM::Entity ->) : Nil
    id_hash = id.values.join " "

    if (klass = @identity_map[entity_class]?) && (entity = klass[id_hash]?)
      yield entity
    end
  end

  private def has_missing_ids_which_are_foreign_keys?(class_metadata : AORM::Mapping::ClassBase, id_arr : Array(AORM::Mapping::Value)) : Bool
    # TODO: Handle FKs when associations are implemented
    false
  end

  # TODO: Abstract the id flattening I guess
  private def flatten_id(id_arr : Array(AORM::Mapping::Value)) : Hash(String, AORM::Mapping::Value)
    id_arr.each_with_object(Hash(String, AORM::Mapping::Value).new) do |id, id_hash|
      id_hash[id.name] = id
    end
  end
end
