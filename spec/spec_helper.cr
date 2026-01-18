require "spec"
require "../src/athena-orm"
require "athena-spec"

require "./models/**"

ASPEC.run_all

class MockUnitOfWork < AORM::UnitOfWork
  @mock_data_changesets = Hash(AORM::Entity, Hash(String, AORM::UnitOfWork::Change)).new.compare_by_identity
  @persister_mock = Hash(AORM::Entity.class, AORM::Persisters::Entity::Interface).new.compare_by_identity

  def entity_persister(entity_class : AORM::Entity.class) : AORM::Persisters::Entity::Interface
    @persister_mock[entity_class]? || super
  end

  def set_entity_persister(entity_class : AORM::Entity.class, persister : AORM::Persisters::Entity::Basic) : Nil
    @persister_mock[entity_class] = persister
  end
end

class MockEntityManager < AORM::EntityManager
  setter uow_mock : AORM::UnitOfWork? = nil

  def initialize(connection : DB::Connection)
    # TODO: Setup config?
    super connection
  end

  def unit_of_work : AORM::UnitOfWork
    @uow_mock || super
  end
end

class MockEntityPersister < AORM::Persisters::Entity::Basic
  record PostInsert, generated_id : Int32, entity : AORM::Entity

  getter execute_insert_call_count : Int32 = 0
  getter inserts : Array(AORM::Entity) = [] of AORM::Entity
  getter updates : Array(AORM::Entity) = [] of AORM::Entity
  getter deletes : Array(AORM::Entity) = [] of AORM::Entity
  setter mock_id_generator : AORM::Mapping::GeneratedValueStrategy? = nil
  getter? exists_called : Bool = false

  @post_insert_ids = Array(PostInsert).new
  @identity_column_counter : Int32 = 0

  def add_insert(entity : AORM::Entity) : Nil
    @inserts << entity

    if !@mock_id_generator.try(&.identity?) && !@class_metadata.identifier_identity?
      return
    end

    id = @identity_column_counter += 1
    @post_insert_ids << PostInsert.new id, entity
  end

  def execute_inserts : Nil
    @execute_insert_call_count += 1

    @post_insert_ids.each do |pi|
      @em.unit_of_work.assign_post_insert_id pi.entity, pi.generated_id
    end
  end

  def update(entity : AORM::Entity) : Nil
    @updates << entity
  end

  def exists(entity : AORM::Entity) : Nil
    @exists_called = true

    false
  end

  def delete(entity : AORM::Entity) : Bool
    @deletes << entity

    true
  end

  def reset : Nil
    @execute_insert_call_count = 0
    @exists_called = false
    @identity_column_counter = 0
    @inserts.clear
    @updates.clear
    @deletes.clear
  end
end

class MockStatement < DB::Statement
  def perform_query(args : Enumerable) : DB::ResultSet
    MockResultSet.new(self)
  end

  def perform_exec(args : Enumerable) : DB::ExecResult
    ::DB::ExecResult.new(
      rows_affected: 1,
      last_insert_id: 1_i64
    )
  end
end

class MockConnection < DB::Connection
  @last_insert_ids : Array(AORM::Mapping::Value) = [] of AORM::Mapping::Value

  def self.new
    new DB::Connection::Options.new
  end

  def build_prepared_statement(query) : DB::Statement
    MockStatement.new self, query
  end

  def build_unprepared_statement(query) : DB::Statement
    MockStatement.new self, query
  end

  # Athena::ORM Extensions
  getter database_platform : AORM::Platforms::Platform do
    AORM::Platforms::SQLite.new
  end

  def push_ids(type : T.class, *ids) : Nil forall T
    ids.each do |id|
      @last_insert_ids << AORM::Mapping::ColumnValue(T).new "id", id
    end
  end

  def last_insert_id
    @last_insert_ids.shift.value
  end
end

class MockResultSet < DB::ResultSet
  def move_next : Bool
    true
  end

  def column_count : Int32
    0
  end

  def column_name(index : Int32) : String
    "id"
  end

  def read
    1_i64
  end

  def next_column_index : Int32
    0
  end
end

abstract struct ORMTestCase
  protected def test_entity_manager : MockEntityManager
    self.create_test_entity_manager_with_platform Platforms::SQLite.new
  end

  protected def create_test_entity_manager_with_platform(platform : Platforms::Platform) : MockEntityManager
    self.build_test_entity_manager_with_platform(
      self.create_connection_mock(platform)
    )
  end

  private def build_test_entity_manager_with_platform(connection : DB::Connection) : MockEntityManager
  end

  private def create_connection_mock(platform : Platforms::Platform) : MockConnection
    MockConnection.new
  end
end
