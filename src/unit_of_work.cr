class Athena::ORM::UnitOfWork
  enum EntityState
    Managed
    New
    Detached
    Removed
  end

  @entity_map : Hash(AORM::Entity.class, Hash(UInt64, AORM::Entity)) = {} of AORM::Entity.class => Hash(UInt64, AORM::Entity)
  @entity_states = Hash(UInt64, EntityState).new

  # Pending entity deltions
  @entity_deletions = Hash(UInt64, AORM::Entity).new

  # Pending entity insertions
  @entity_inserstions = Hash(UInt64, AORM::Entity).new

  def initialize(@em : AORM::EntityManagerInterface); end

  def commit(entity : AORM::Entity? = nil) : Nil
    # TODO: compute changeset(s) to skip executing queries
    # for entities that haven't changed

    # Nothing to do
    return if @entity_deletions.empty? && @entity_inserstions.empty

    # TODO: determine the order of the inserts
    # so that referential integrity is maintained.

    @em.transaction do |tx|
      @entity_inserstions.each do |obj_id, entity|
      end

      @entity_deletions.each do |obj_id, entity|
      end
    end
  end

  def persist(entity : AORM::Entity) : Nil
    visited = Set(UInt64).new

    self.persist entity, visited
  end

  private def persist(entity : AORM::Entity, visited : Set(UInt64)) : Nil
    obj_id = entity.object_id

    return unless visited.add? obj_id

    case self.entity_state(entity, :new)
    in .managed? then return # TODO: Handle change tracking?
    in .new?     then self.persist_new entity
    in .removed? # Remanage the entity
      @entity_deletions.delete obj_id
      self.add_to_entity_map entity

      @entity_states[obj_id] = :new
    in .detached? then return # noop
    end

    # TODO: Handle cascade for nested entities
  end

  def remove(entity : AORM::Entity) : Nil
    visited = Set(UInt64).new

    self.remove entity, visited
  end

  private def persist_new(entity : AORM::Entity) : Nil
    obj_id = entity.object_id

    # TODO: Handle the entity's IDGenerator

    @entity_states[obj_id] = :new
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

    # TODO: Handle primary key here
    # can skip composite keys for now

    # TODO: Also handle the case where
    # the state is not assumed
    raise NotImplementedError.new "Unhandleable state"
  end

  def add_to_entity_map(entity : AORM::Entity) : Nil
  end
end
