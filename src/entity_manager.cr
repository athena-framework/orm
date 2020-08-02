require "./entity_manager_interface"
require "./repository_interface"
require "./unit_of_work"

class Athena::ORM::EntityManager
  include Athena::ORM::EntityManagerInterface

  getter connection : DB::Connection
  getter? closed : Bool = false
  getter unit_of_work : AORM::UnitOfWork { AORM::UnitOfWork.new self }

  @repository_factory : AORM::RepositoryFactoryInterface

  def initialize(@connection : DB::Connection)
    @repository_factory = AORM::DefaultRepositoryFactory.new
  end

  # TODO: Support composite PKs via #find.
  def find(entity_class : AORM::Entity.class, id : Hash(String, Int | String) | Int | String, lock_mode : AORM::LockMode? = nil, lock_version : Int32? = nil) : AORM::Entity?
    class_metadata = entity_class.entity_class_metadata
    entity_class = class_metadata.entity_class

    # TODO: Handle locking

    unless id.is_a? Hash
      id = {class_metadata.single_identifier_field_name => id}
    end

    uow = self.unit_of_work

    uow.try_get_by_id(id, entity_class) do |entity|
      pp entity

      return nil unless entity == entity_class

      # TODO: Handle locking

      return entity
    end

    persister = uow.entity_persister entity_class

    # TODO: Handle locking

    persister.load_by_id id
  end

  def persist(entity : AORM::Entity) : Nil
    self.unless_closed do
      self.unit_of_work.persist entity
    end
  end

  def remove(entity : AORM::Entity) : Nil
    self.unless_closed do
      self.unit_of_work.remove entity
    end
  end

  def refresh(entity : AORM::Entity) : Nil
    NotImplementedError.new "TODO: Implement this"
  end

  def detach(entity : AORM::Entity) : Nil
    NotImplementedError.new "TODO: Implement this"
  end

  def merge(entity : AORM::Entity) : Nil
    NotImplementedError.new "TODO: Implement this"
  end

  def flush(entity : AORM::Entity? = nil) : Nil
    self.unless_closed do
      self.unit_of_work.commit entity
    end
  end

  def clear(entity : AORM::Entity? = nil) : Nil
    self.unit_of_work.clear

    # TODO: Handle eventing (onClear)
  end

  def repository(entity_class : AORM::Entity.class) : AORM::RepositoryInterface
    # TODO: Figure out how to handle this, probably should use overloads for this
    # to give type saftey & prevent need for .as()
    @repository_factory.repository self, entity_class
  end

  def contains(entity : AORM::Entity) : Bool
    self.unit_of_work.scheduled_for_insert?(entity) || self.unit_of_work.has?(entity) && !self.unit_of_work.scheduled_for_delete?(entity)
  end

  def copy(entity : AORM::Entity, deep : Bool = false) : AORM::Entity
    case deep
    in true  then entity.clone
    in false then entity.dup
    end
  end

  def transaction(& : DB::Transaction ->) : Nil
    @connection.transaction do |tx|
      yield tx
    end
  end

  def close : Nil
    self.clear

    @closed = true
  end

  private def unless_closed(&) : Nil
    # Use an actual Exception type for this
    raise "EM IS CLOSED" if @closed
    yield
  end
end
