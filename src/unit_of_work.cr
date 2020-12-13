class Athena::ORM::UnitOfWork
  record Change, old : AORM::Mapping::Value?, new : AORM::Mapping::Value

  enum EntityState
    Managed
    New
    Detached
    Removed
  end

  @identity_map = Hash(AORM::Entity.class, Hash(String, AORM::Entity)).new

  @entity_identifiers = Hash(AORM::Entity, Hash(String, AORM::Mapping::Value)).new

  @entity_states = Hash(AORM::Entity, EntityState).new

  # Pending entity deletions
  @entity_deletions = Set(AORM::Entity).new

  # Pending entity insertions
  @entity_insertions = Set(AORM::Entity).new

  # Pending entity updates
  @entity_updates = Set(AORM::Entity).new

  @entity_persisters = Hash(AORM::Entity.class, AORM::Persisters::Entity::Interface).new

  @original_entity_data = Hash(AORM::Entity, Hash(String, AORM::Mapping::Value)).new
  @entity_change_sets = Hash(AORM::Entity, Hash(String, Change)).new
  @orphan_removals = Set(AORM::Entity).new

  @non_cascaded_new_detected_entities = Hash(AORM::Entity, Tuple(AORM::Mapping::AssociationMetadataBase, AORM::Entity)).new

  def initialize(@em : AORM::EntityManagerInterface); end

  def commit : Nil
    # TODO: Handle eventing (preFlush)

    self.compute_changesets

    # Nothing to do
    return if @entity_deletions.empty? && @entity_insertions.empty? && @entity_updates.empty?

    p! @entity_insertions
    # p! @entity_updates
    # p! @entity_deletions

    self.assert_that_there_are_no_unintentionally_non_persisted_associations

    # TODO: determine the order of the inserts
    # so that referential integrity is maintained.

    @em.transaction do
      @entity_insertions.each do |entity|
        self.execute_inserts @em.class_metadata entity.class
      end

      @entity_updates.each do |entity|
        self.execute_updates @em.class_metadata entity.class
      end

      @entity_deletions.each do |entity|
        self.execute_deletions @em.class_metadata entity.class
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

  private def assert_that_there_are_no_unintentionally_non_persisted_associations : Nil
    entities_needing_persist = @entity_insertions - @non_cascaded_new_detected_entities.keys

    @non_cascaded_new_detected_entities.clear

    unless entities_needing_persist.empty?
      raise "NEW NON CASCADE ENTITY"
    end
  end

  private def post_commit_cleanup : Nil
    @entity_insertions.clear
    @entity_updates.clear
    @entity_deletions.clear
    @entity_change_sets.clear
    @orphan_removals.clear
  end

  private def execute_inserts(class_metadata : AORM::Mapping::ClassBase) : Nil
    entity_class = class_metadata.entity_class
    persister = self.entity_persister class_metadata.entity_class
    generation_plan = class_metadata.value_generation_plan

    @entity_insertions.each do |entity|
      next if entity_class != @em.class_metadata(entity.class).entity_class

      persister.insert entity

      if generation_plan.contains_deferred?
        id = persister.identifier entity

        @entity_identifiers[entity] = self.flatten_id id
        @entity_states[entity] = :managed

        id.each do |i|
          @original_entity_data[entity][i.name] = i
        end

        self.add_to_identity_map entity
      end

      @entity_insertions.delete entity

      # TODO: Handle eventing (postPersist)
    end
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

    case self.entity_state(entity, :new)
    in .managed? then return # TODO: Handle change tracking
    in .new?     then self.persist_new class_metadata, entity
    in .removed? # Remanage the entity
      @entity_deletions.delete entity
      self.add_to_identity_map entity

      @entity_states[entity] = :managed
    in .detached? then return # noop
    end

    # TODO: Handle cascade for nested entities
    pp entity
  end

  def remove(entity : AORM::Entity) : Nil
    visited = Set(UInt64).new

    self.remove entity, visited
  end

  private def remove(entity : AORM::Entity, visited : Set(AORM::Entity)) : Nil
    return unless visited.add? entity

    # TODO: Handle cascade for nested models

    case self.entity_state entity
    in .new?     then return                                  # noop
    in .removed? then return                                  # noop
    in .managed? then self.schedule_for_delete entity         # TODO: Handle eventing (preRemove)
    in .detached? then raise "Cannot removed detached entity" # TODO: Make this an actual exception
    end
  end

  private def persist_new(class_metadata : AORM::Mapping::ClassBase, entity : AORM::Entity) : Nil
    generation_plan = class_metadata.value_generation_plan
    persister = self.entity_persister class_metadata.entity_class
    generation_plan.execute_immediate @em, entity

    unless generation_plan.contains_deferred?
      id = persister.identifier entity

      unless self.has_missing_ids_which_are_foreign_keys? class_metadata, id
        @entity_identifiers[entity] = self.flatten_id id
      end
    end

    @entity_states[entity] = :managed
    self.schedule_for_insert entity
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
      @entity_insertions.delete entity
      @entity_identifiers.delete entity
      @entity_states.delete entity

      return
    end

    return unless self.is_in_identity_map entity

    self.remove_from_identity_map entity

    @entity_updates.delete entity

    unless @entity_deletions.includes? entity
      @entity_deletions[entity] = entity
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

  def entity_state(entity : AORM::Entity, assume : EntityState? = nil) : EntityState
    if state = @entity_states[entity]?
      return state
    end

    return assume if assume

    class_metadata = @em.class_metadata entity.class
    persister = self.entity_persister class_metadata.entity_class
    id = persister.identifier entity

    return EntityState::New if id.empty?

    flat_id = self.flatten_id id

    property = class_metadata.property(class_metadata.single_identifier_field_name)

    # TODO: Handle AssociationMetadata
    if (
         class_metadata.is_identifier_composite? ||
         !property.is_a?(AORM::Mapping::FieldMetadata) ||
         !property.as(AORM::Mapping::FieldMetadata).has_value_generator?
       )
      # TODO: Handle versioned fields

      self.try_get flat_id, class_metadata.root_class do
        return EntityState::Detached
      end

      # TODO: Handle DB exists lookup

      return EntityState::New
    end

    # TODO: Handle deferred value generation plans

    raise NotImplementedError.new "Unhandleable state"
  end

  def change_set(entity : AORM::Entity) : Hash(String, Change)
    unless @entity_change_sets.has_key? entity
      return Hash(String, Change).new
    end

    @entity_change_sets[entity]
  end

  def entity_identifier(entity : AORM::Entity) : Hash(String, AORM::Mapping::Value)
    @entity_identifiers[entity]
  end

  protected def entity_persister(entity_class : AORM::Entity.class) : AORM::Persisters::Entity::Interface
    if persister = @entity_persisters[entity_class]?
      return persister
    end

    class_metadata = @em.class_metadata entity_class

    # TODO: Support other types of persisters
    # TODO: Handle cacheing

    @entity_persisters[entity_class] = AORM::Persisters::Entity::Basic.new @em, class_metadata
  end

  protected def try_get_by_id(id : Hash(String, Int | String), entity_class : AORM::Entity.class) : AORM::Entity?
    id_hash = id.values.join " "

    if (klass = @identity_map[entity_class]?) && (entity = klass[id_hash]?)
      yield entity
    end
  end

  def add_to_identity_map(entity : AORM::Entity) : Bool
    class_metadata = @em.class_metadata entity.class
    identifier = @entity_identifiers[entity]?

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
    return false if !@entity_identifiers.has_key?(entity) || @entity_identifiers[entity].empty?

    class_metadata = @em.class_metadata entity.class
    id_hash = @entity_identifiers[entity].values.join " "

    @identity_map.has_key?(class_metadata.root_class) && @identity_map[class_metadata.root_class].has_key?(id_hash)
  end

  def remove_from_identity_map(entity : AORM::Entity) : Bool
    class_metadata = @em.class_metadata entity.class
    id_hash = @entity_identifiers[entity].values.join " "

    # TODO: Use proper exception type
    raise "Entity has no identity" if id_hash.blank?

    class_name = class_metadata.root_class

    return true if @identity_map.has_key?(class_name) && @identity_map.has_key?(id_hash)

    false
  end

  private def compute_changesets : Nil
    self.compute_scheduled_inserts_change_sets

    @identity_map.each do |entity_class, entity_hash|
      class_metadata = @em.class_metadata entity_class

      # TODO: Skip readonly classes
      # TODO: Handle change tracking policies

      entity_hash.each_value do |entity|
        # TODO: Skip ghosts/proxies

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

  private def compute_change_set(class_metadata : AORM::Mapping::ClassBase, entity : AORM::Entity) : Nil
    # TODO: Handle read only objects
    # TODO: Handle inheritence types
    # TODO: Handle eventing (preFlush) & ~ListenersInvoker::INVOKE_MANAGER???

    actual_data = Hash(String, AORM::Mapping::Value).new

    class_metadata.each do |property|
      column_value = property.get_value entity
      name = property.name

      if (
           !class_metadata.is_identifier?(name) ||
           !property.is_a?(AORM::Mapping::FieldMetadata) ||
           !property.as(AORM::Mapping::FieldMetadata).value_generator.try(&.type.identity?)
         ) # TODO: Handle versioned columns
        actual_data[name] = column_value
      end
    end

    if !@original_entity_data.has_key? entity
      # entity is new or managed but not fully persisted yet

      @original_entity_data[entity] = actual_data
      changeset = Hash(String, Change).new

      actual_data.each do |name, v|
        property = class_metadata.property(name)

        # TODO: Handle non ToOne associations
        if property.is_a?(AORM::Mapping::FieldMetadata) || (property.is_a?(AORM::Mapping::ToOneAssociationMetadata) && property.is_owning_side?)
          changeset[name] = Change.new nil, v
        end
      end

      @entity_change_sets[entity] = changeset
    else
      # entity is fully managed
      original_data = @original_entity_data[entity]
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
        when AORM::Mapping::FieldMetadata
          # TODO: Handle notify change tracking policy
          changeset[name] = Change.new original_value, actual_value
        when AORM::Mapping::ToOneAssociationMetadata
          changeset[property.name] = Change.new original_value, actual_value if property.is_owning_side?
          # self.schedule_orphan_removal original_value.value if !original_data.nil? && property.is_orphan_removal?

          # TODO: Handle non ToOne associations
        else
          # noop
        end
      end

      unless changeset.empty?
        @entity_change_sets[entity] = changeset
        @original_entity_data[entity] = actual_data
        @entity_updates.add entity
      end
    end

    # Look for changes in associations
    class_metadata.each do |property|
      # TODO: Handle non ToOne associations
      next unless property.is_a? AORM::Mapping::AssociationMetadata

      value = property.get_value entity

      next if value.value.nil?

      # Compute association changeset
      self.compute_change_set property, value.value.as AORM::Entity
    end
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

  protected def manage_entity(entity : AORM::Entity) : AORM::Entity
    class_metadata = @em.class_metadata entity.class
    persister = self.entity_persister class_metadata.entity_class

    @entity_identifiers[entity] = flatten_id persister.identifier entity
    @entity_states[entity] = :managed
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
    id_arr.any? { |value| value.value.nil? && class_metadata.property(value.name).is_a?(AORM::Mapping::AssociationMetadata) }
  end

  # TODO: Abstract the id flattening I guess
  private def flatten_id(id_arr : Array(AORM::Mapping::Value)) : Hash(String, AORM::Mapping::Value)
    id_arr.each_with_object(Hash(String, AORM::Mapping::Value).new) do |id, id_hash|
      id_hash[id.name] = id
    end
  end
end
