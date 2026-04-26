require "spec"
require "../src/athena-orm"
require "athena-spec"

require "./models/**"

ASPEC.run_all

class MockPlatform < AORM::Platforms::Platform
  setter db_boolean : Bool?
  setter crystal_boolean : Bool?

  def initialize(
    *,
    @db_boolean : Bool? = nil,
    @crystal_boolean : Bool? = nil,
  ); end

  def boolean_type_declaration_sql(column : AORM::Schema::Column) : String
    "BOOLEAN"
  end

  def integer_type_declaration_sql(column : AORM::Schema::Column) : String
    "INTEGER"
  end

  def big_int_type_declaration_sql(column : AORM::Schema::Column) : String
    "BIGINT"
  end

  private def common_integer_type_declaration_sql(column : AORM::Schema::Column) : String
    ""
  end

  def convert_booleans_to_db_value(value) : Bool?
    @db_boolean.try { |v| return v } || super
  end

  def convert_from_boolean(value) : Bool?
    @crystal_boolean.try { |v| return v } || super
  end
end

class MockUnitOfWork < AORM::UnitOfWork
  @mock_data_changesets = Hash(AORM::Entity, Hash(String, AORM::UnitOfWork::Change)).new.compare_by_identity
  @persister_mock = Hash(AORM::Entity.class, AORM::Persisters::Entity::Interface).new.compare_by_identity

  def entity_persister(entity_class : AORM::Entity.class) : AORM::Persisters::Entity::Interface
    @persister_mock[entity_class]? || super
  end

  def set_entity_persister(entity_class : AORM::Entity.class, persister : AORM::Persisters::Entity::Basic) : Nil
    @persister_mock[entity_class] = persister
  end

  # Test access to the topologically-sorted insert order.
  def insert_execution_order : Array(AORM::Entity)
    self.compute_insert_execution_order
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

  # Test access to the protected `prepare_insert_data`.
  def insert_data_for(entity : AORM::Entity) : Hash(String, Hash(String, AORM::Mapping::Value))
    self.prepare_insert_data entity
  end

  # Test access to the protected `prepare_update_data`.
  def update_data_for(entity : AORM::Entity) : Hash(String, Hash(String, AORM::Mapping::Value))
    self.prepare_update_data entity
  end

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

  # Test fixture: canned entity returned by `load_by_id`. Setting it overrides
  # the real DB-fetching behavior so repo / find tests can exercise the
  # delegation path without standing up a real result set.
  setter mock_load_by_id_result : AORM::Entity? = nil
  getter load_by_id_calls : Array(Hash(String, Int32 | Int64 | String)) = [] of Hash(String, Int32 | Int64 | String)

  # Test fixture: canned entity returned by `load`. Captures every call's
  # criteria and limit so specs can assert what the repository forwarded.
  setter mock_load_result : AORM::Entity? = nil
  record LoadCall, criteria : Hash(String, Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil | Array(Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil)), limit : Int32?
  getter load_calls : Array(LoadCall) = [] of LoadCall

  # Test fixture: canned array returned by `load_all`. Captures criteria,
  # order_by, limit, and offset so specs can assert the repo's forwarding.
  setter mock_load_all_result : Array(AORM::Entity) = [] of AORM::Entity
  record LoadAllCall,
    criteria : Hash(String, Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil | Array(Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil)),
    order_by : Hash(String, String)?,
    limit : Int32?,
    offset : Int32?
  getter load_all_calls : Array(LoadAllCall) = [] of LoadAllCall

  def load_by_id(id : Hash(String, Int | String)) : AORM::Entity?
    widened = id.transform_values { |v| v.is_a?(Int) ? v.to_i64.as(Int32 | Int64 | String) : v.as(Int32 | Int64 | String) }
    @load_by_id_calls << widened
    @mock_load_by_id_result
  end

  # Test fixture: when set, `load` simulates a fresh row by calling
  # `uow.create_entity` with this data, which runs the refresh-hint code path
  # for already-managed entities. Used for `UoW#refresh` specs.
  setter mock_refresh_data : Hash(String, DB::Any)? = nil

  def load(
    criteria : Hash(String, _),
    entity : AORM::Entity? = nil,
    association : AORM::Mapping::Association? = nil,
    hints : AORM::Query::Hints = AORM::Query::Hints.new,
    lock_mode : AORM::LockMode? = nil,
    limit : Int? = nil,
    order_by : Hash(String, String)? = nil,
  ) : AORM::Entity?
    widened_criteria = Hash(String, DB::Any | Array(DB::Any)).new
    criteria.each { |k, v| widened_criteria[k] = v.as(DB::Any | Array(DB::Any)) }
    @load_calls << LoadCall.new(widened_criteria, limit.try(&.to_i32))

    if (data = @mock_refresh_data) && hints.refresh? && entity
      @em.unit_of_work.create_entity entity.class, data, hints
      return entity
    end

    @mock_load_result
  end

  def load_all(
    criteria : Hash(String, _) = Hash(String, DB::Any).new,
    order_by : Hash(String, String)? = nil,
    limit : Int? = nil,
    offset : Int32? = nil,
  ) : Array(AORM::Entity)
    @load_all_calls << LoadAllCall.new(
      criteria.transform_values { |v| v.as(DB::Any | Array(DB::Any)) },
      order_by,
      limit.try(&.to_i32),
      offset
    )
    @mock_load_all_result
  end

  # Test fixture: canned count returned by `count`. Captures the criteria so
  # specs can assert what the repository forwarded.
  setter mock_count_result : Int32 = 0
  getter count_calls : Array(Hash(String, Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil | Array(Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil))) = [] of Hash(String, Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil | Array(Bool | Float32 | Float64 | Int32 | Int64 | Slice(UInt8) | String | Time | Nil))

  def count(criteria : Hash(String, _) = Hash(String, DB::Any).new) : Int32
    @count_calls << criteria.transform_values { |v| v.as(DB::Any | Array(DB::Any)) }
    @mock_count_result
  end

  def reset : Nil
    @execute_insert_call_count = 0
    @exists_called = false
    @identity_column_counter = 0
    @inserts.clear
    @updates.clear
    @deletes.clear
    @load_by_id_calls.clear
    @load_calls.clear
    @load_all_calls.clear
    @count_calls.clear
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

# Result set that yields a fixed list of `Hash(String, DB::Any)` rows.
# Implements just enough of `DB::ResultSet` for hydrator code paths (`column_names`, `each`, `read`, `move_next`, `close`). Use this when a spec needs to drive hydration end-to-end with deterministic row data.
class FakeResultSet < DB::ResultSet
  def initialize(@rows : Array(Hash(String, DB::Any)))
    statement = MockStatement.new(MockConnection.new, "")
    super(statement)
    @row_idx = -1
    @col_idx = 0
    @columns = @rows.empty? ? [] of String : @rows.first.keys
  end

  def move_next : Bool
    @row_idx += 1
    @col_idx = 0
    @row_idx < @rows.size
  end

  def column_count : Int32
    @columns.size
  end

  def column_name(index : Int32) : String
    @columns[index]
  end

  def read
    val = @rows[@row_idx][@columns[@col_idx]]
    @col_idx += 1
    val
  end

  def next_column_index : Int32
    @col_idx
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
