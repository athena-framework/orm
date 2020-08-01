class Athena::ORM::UnitOfWork
  enum EntityState
    Managed
    New
    Detached
    Removed
  end

  @identity_map : Hash(AORM::Entity.class, Hash(String, AORM::Entity)) = {} of AORM::Entity.class => Hash(String, AORM::Entity)

  @entity_identifiers = Hash(UInt64, Hash(String, AORM::Metadata::Value)).new

  @entity_states = Hash(UInt64, EntityState).new

  # Pending entity deltions
  @entity_deletions = Hash(UInt64, AORM::Entity).new

  # Pending entity insertions
  @entity_inserstions = Hash(UInt64, AORM::Entity).new

  @entity_persisters = Hash(AORM::Entity.class, AORM::EntityPersisterInterface).new

  def initialize(@em : AORM::EntityManagerInterface); end

  def commit(entity : AORM::Entity? = nil) : Nil
    # TODO: compute changeset(s) to skip executing queries
    # for entities that haven't changed

    # Nothing to do
    return if @entity_deletions.empty? && @entity_inserstions.empty?

    # TODO: determine the order of the inserts
    # so that referential integrity is maintained.

    @em.transaction do |tx|
      @entity_inserstions.each_value do |entity|
        self.execute_inserts entity.class.entity_class_metadata
      end

      @entity_deletions.each do |obj_id, entity|
        self.execute_deleteions entity.class.entity_class_metadata
      end
    end
  end

  private def execute_inserts(class_metadata : AORM::Metadata::Class) : Nil
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
        # TODO: Update original changeset data

        self.add_to_identity_map entity
      end

      @entity_inserstions.delete obj_id
    end
  end

  private def execute_deleteions(class_metadata : AORM::Metadata::Class) : Nil
    entity_class = class_metadata.entity_class
    persister = self.entity_persister class_metadata.entity_class

    @entity_deletions.each do |obj_id, entity|
      next if entity_class != entity.class.entity_class_metadata.entity_class

      persister.delete entity

      @entity_deletions.delete obj_id
      @entity_identifiers.delete obj_id
      @entity_states.delete obj_id
      # TODO: Delete original data from changeset

      unless class_metadata.is_identifier_composite?
        property = class_metadata.property(class_metadata.single_identifier_field_name).not_nil!

        if property.has_value_generator?
          property.set_value entity, nil
        end
      end

      # TODO: Handle eventing
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

  private def persist_new(class_metadata : AORM::Metadata::Class, entity : AORM::Entity) : Nil
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
  end

  private def remove(entity : AORM::Entity, visited : Set(UInt64)) : Nil
    obj_id = entity.object_id

    return unless visited.add? obj_id

    # TODO: Handle cascade for nested models

    case self.entity_state entity, :new
    in .new?     then return # noop
    in .removed? then return # noop
    in .managed? then self.schedule_for_delete entity
    in .detached? then raise "Cannot removed detached entity" # TODO: Make this an actual exception
    end
  end

  private def schedule_for_delete(entity : AORM::Entity) : Nil
    obj_id = entity.object_id

    unless @entity_inserstions.delete obj_id
      @entity_identifiers.delete obj_id
      @entity_states.delete obj_id

      return
    end

    unless @entity_deletions.has_key? obj_id
      @entity_deletions[obj_id] = entity
      @entity_states[obj_id] = :removed
    end
  end

  def clear(entity : AORM::Entity? = nil) : Nil
    if entity.nil?
      @entity_map.clear
      @entity_states.clear
      @entity_deletions.clear
      @entity_inserstions.clear
    else
      # TODO: Clear for given entity
    end
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

  def add_to_identity_map(entity : AORM::Entity) : Bool
    obj_id = entity.object_id

    class_metadata = entity.class.entity_class_metadata
    identifier = @entity_identifiers[obj_id]?

    if identifier.nil? || identifier.empty?
      # TODO: Use a property exception
      raise "Entity without an identifier"
    end

    class_name = class_metadata.root_class
    id_hash = identifier.values.join " "

    # TODO: Handle primary key here
    # can skip composite keys for now
    return false if @identity_map[class_name].has_key? obj_id

    @identity_map[class_name][id_hash] = entity

    true
  end

  def entity_identifier(entity : AORM::Entity) : Hash(String, AORM::Metadata::Value)
    @entity_identifiers[entity.object_id]
  end

  private def entity_persister(entity_class : AORM::Entity.class) : AORM::EntityPersisterInterface
    if persister = @entity_persisters[entity_class]?
      return persister
    end

    class_metadata = entity_class.entity_class_metadata

    persister = case class_metadata.inheritence_type
                in .none? then AORM::BasicEntityPersister.new @em, class_metadata
                end

    # TODO: Handle cacheing

    @entity_persisters[entity_class] = persister
  end

  private def try_get(id : Hash(String, AORM::Metadata::Value), entity_class : AORM::Entity.class, & : AORM::Entity ->) : Nil
    id_hash = id.values.join " "

    if (klass = @identity_map[entity_class]?) && (entity = klass[id_hash]?)
      yield entity
    end
  end

  private def has_missing_ids_which_are_foreign_keys?(class_metadata : AORM::Metadata::Class, id_arr : Array(AORM::Metadata::Value)) : Bool
    # TODO: Handle FKs when associations are implemented
    false
  end

  # TODO: Abstract the id flattening I guess
  private def flatten_id(id_arr : Array(AORM::Metadata::Value)) : Hash(String, AORM::Metadata::Value)
    id_arr.each_with_object(Hash(String, AORM::Metadata::Value).new) do |id, id_hash|
      id_hash[id.name] = id
    end
  end
end
