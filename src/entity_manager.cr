require "./entity_manager_interface"

class Athena::ORM::EntityManager
  include Athena::ORM::EntityManagerInterface

  getter connection : AORM::Connection
  getter? closed : Bool = false
  getter unit_of_work : AORM::UnitOfWork { AORM::UnitOfWork.new self }
  getter! metadata_factory : AORM::Mapping::ClassFactory

  @repository_factory : AORM::RepositoryFactoryInterface

  def initialize(connection : DB::Connection)
    @connection = AORM::Connection.new(connection)
    @repository_factory = AORM::DefaultRepositoryFactory.new

    metadata_factory = AORM::Mapping::ClassFactory.new
    metadata_factory.entity_manager = self

    @metadata_factory = metadata_factory
  end

  def find(
    entity_class : T.class,
    id : Hash(String, Int | String) | Int | String,
    lock_mode : AORM::LockMode? = nil,
    lock_version : Int32? = nil,
  ) : AORM::Entity? forall T
    {% raise "entity_class must be an AORM::Entity.class, not '#{T}'." unless T <= AORM::Entity %}

    class_metadata = self.class_metadata entity_class
    entity_class = class_metadata.entity_class

    # TODO: Handle locking

    # TODO: Support composite PKs via #find.
    unless id.is_a? Hash
      id = {class_metadata.single_identifier_field_name => id}
    end

    uow = self.unit_of_work

    uow.try_get_by_id(id, entity_class) do |entity|
      return nil if entity.class != entity_class

      # TODO: Handle locking

      return entity.as T?
    end

    persister = uow.entity_persister entity_class

    # TODO: Handle locking

    persister.load_by_id(id).as T?
  end

  def find!(
    entity_class : T.class,
    id : Hash(String, Int | String) | Int | String,
    lock_mode : AORM::LockMode? = nil,
    lock_version : Int32? = nil,
  ) : AORM::Entity forall T
    self.find(entity_class, id, lock_mode, lock_version) || raise AORM::Exceptions::NoResult.new
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

  def clear(entity_class : AORM::Entity.class | Nil = nil) : Nil
    self.unit_of_work.clear

    # TODO: Handle eventing (onClear)
  end

  def class_metadata(for entity_class : AORM::Entity.class) : AORM::Mapping::ClassInterface
    self.metadata_factory.metadata entity_class
  end

  macro finished
    {% for entity in Athena::ORM::Entity.all_subclasses.reject &.abstract? %}
      # Define a `#repository` overload for entities who have custom repos.
      {% if (entity_ann = entity.annotation(AORMA::Entity)) && (repository_class = entity_ann[:repository_class]) %}
        def repository(entity_class : {{entity.id}}.class) : {{repository_class.id}}
          @repository_factory.repository(self, entity_class).as {{repository_class.id}}
        end
      {% end %}
    {% end %}
  end

  def repository(entity_class : AORM::Entity.class) : AORM::RepositoryInterface
    @repository_factory.repository self, entity_class
  end

  def contains(entity : AORM::Entity) : Bool
    self.unit_of_work.scheduled_for_insert?(entity) || self.unit_of_work.has?(entity) && !self.unit_of_work.scheduled_for_delete?(entity)
  end

  def transaction(& : DB::Transaction ->) : Nil
    @connection.transaction do |tx|
      yield tx
    end
  end

  def close : Nil
    self.clear
    @connection.release

    @closed = true
  end

  def hydrator(mode : HydrationMode) : AORM::Internal::Hydrators::Abstract
    case mode
    in .object?        then AORM::Internal::Hydrators::Object.new self
    in .simple_object? then AORM::Internal::Hydrators::SimpleObject.new self
    end
  end

  # Creates a native SQL query with explicit result set mapping.
  def create_native_query(sql : String, rsm : Query::ResultSetMapping) : NativeQuery
    NativeQuery.new(self, sql, rsm)
  end

  private def unless_closed(&) : Nil
    # Use an actual Exception type for this
    raise "EM IS CLOSED" if @closed
    yield
  end
end
