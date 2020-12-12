require "./entity_manager_interface"

class Athena::ORM::EntityManager
  include Athena::ORM::EntityManagerInterface

  getter connection : DB::Database
  getter? closed : Bool = false
  getter unit_of_work : AORM::UnitOfWork { AORM::UnitOfWork.new self }
  getter metadata_factory : AORM::Mapping::ClassFactory { AORM::Mapping::ClassFactory.new self }

  @repository_factory : AORM::RepositoryFactoryInterface

  def initialize(@connection : DB::Database)
    @repository_factory = AORM::DefaultRepositoryFactory.new
  end

  # TODO: Support composite PKs via #find.
  def find(
    entity_class : AORM::Entity.class,
    id : Hash(String, Int | String) | Int | String,
    lock_mode : AORM::LockMode? = nil,
    lock_version : Int32? = nil
  ) : AORM::Entity?
    class_metadata = self.class_metadata entity_class
    entity_class = class_metadata.entity_class

    # TODO: Handle locking

    unless id.is_a? Hash
      id = {class_metadata.single_identifier_field_name => id}
    end

    uow = self.unit_of_work

    uow.try_get_by_id(id, entity_class) do |entity|
      return nil if entity.class != entity_class

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

  def flush : Nil
    self.unless_closed do
      self.unit_of_work.commit
    end
  end

  def clear(entity : AORM::Entity? = nil) : Nil
    self.unit_of_work.clear

    # TODO: Handle eventing (onClear)
  end

  def class_metadata(for entity_class : AORM::Entity.class) : AORM::Mapping::ClassBase
    self.metadata_factory.metadata entity_class
  end

  # TODO: Figure out if there is a better way to handle this
  macro finished
    {% for repo in Athena::ORM::EntityRepository.all_subclasses.reject &.abstract? %}
      {% entity_class = repo.name.gsub(/Repository$/, "") %}
      def repository(entity_class : {{entity_class.id}}.class) : {{repo.id}}
        @repository_factory.repository(self, entity_class).as {{repo.id}}
      end
    {% end %}
  end

  def repository(entity_class : AORM::Entity.class) : AORM::RepositoryInterface
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

  def hydrator(mode : HydrationMode) : AORM::Hydrators::Abstract
    case mode
    in .object?        then AORM::Hydrators::Object.new self
    in .simple_object? then AORM::Hydrators::SimpleObject.new self
    end
  end

  private def unless_closed(&) : Nil
    # Use an actual Exception type for this
    raise "EM IS CLOSED" if @closed
    yield
  end
end
