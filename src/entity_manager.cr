require "./entity_manager_interface"
require "./repository_interface"
require "./unit_of_work"

class Athena::ORM::EntityManager
  include Athena::ORM::EntityManagerInterface

  getter connection : DB::Connection
  getter? closed : Bool = false
  getter unit_of_work : AORM::UnitOfWork { AORM::UnitOfWork.new self }

  def initialize(@connection : DB::Connection); end

  def find(entity_class : AORM::Entity.class, id : _) : AORM::Entity?
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
