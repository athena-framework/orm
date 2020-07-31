require "db"

require "./sequence_generator"
require "./value_generation_plan_interface"
require "./value_generation_executor_interface"
require "./column_value_generator_executor"
require "./single_value_generation_plan"

require "./metadata/*"
require "./platforms/*"
require "./types/*"

require "./entity_persister_interface"
require "./basic_entity_persister"
require "./entity_manager"
require "./entity"

# Convenience alias to make referencing `Athena::ORM` types easier.
alias AORM = Athena::ORM

module Athena::ORM
  VERSION = "0.1.0"

  annotation Column; end
  annotation ID; end
  annotation GeneratedValue; end
end

class FakeStatement < DB::Statement
  protected def perform_query(args : Enumerable) : DB::ResultSet
    FieldEmitter.new
  end

  protected def perform_exec(args : Enumerable) : DB::ExecResult
    DB::ExecResult.new 0_i64, 0_i64
  end
end

class FakeContext
  include DB::ConnectionContext

  def uri : URI
    URI.new ""
  end

  def prepared_statements? : Bool
    false
  end

  def discard(connection); end

  def release(connection); end
end

class DB::Connection
  def database_platform
    AORM::Platforms::Postgres.new
  end
end

class FakeConnection < DB::Connection
  def initialize
    @context = FakeContext.new
    @prepared_statements = false
  end

  def build_unprepared_statement(query : String) : FakeStatement
    FakeStatement.new self
  end

  def build_prepared_statement(query : String) : FakeStatement
    FakeStatement.new self
  end

  def database_platform
    AORM::Platforms::Postgres.new
  end
end

class FieldEmitter < DB::ResultSet
  private alias EmitterType = DB::Any

  # 1. Override `#move_next` to move to the next row.
  # 2. Override `#read` returning the next value in the row.
  # 3. (Optional) Override `#read(t)` for some types `t` for which custom logic other than a simple cast is needed.
  # 4. Override `#column_count`, `#column_name`.

  @position = 0
  @field_position = 0
  @values = [] of EmitterType

  def initialize
    @statement = FakeStatement.new FakeConnection.new
  end

  def _set_values(values : Array(EmitterType))
    @values = [] of EmitterType
    values.each do |v|
      @values << v
    end
  end

  def move_next : Bool
    @position += 1
    @field_position = 0
    @position < @values.size
  end

  def read
    if @position >= @values.size
      raise "Overread"
    end

    @values[@position].tap do
      @position += 1
    end
  end

  def column_count : Int32
    @values.size
  end

  def column_name(index : Int32) : String
    "Column #{index}"
  end
end

# enum Test
#   One
#   Two
# end

# struct TestEnumType < Athena::ORM::Types::Enum(Test); end

# AORM::Types::Type.add_type TestEnumType, TestEnumType

class User < Athena::ORM::Entity
  def initialize(@name : String); end

  @[AORM::Column]
  @[AORM::ID]
  @[AORM::GeneratedValue]
  getter! id : Int64

  @[AORM::Column]
  property name : String
end

# pp User.entity_class_metadata

# rs = FieldEmitter.new.tap do |e|
#   e._set_values([1_i64, "Jim"])
# end

# u = User.from_rs rs

require "pg"

DB.open "postgres://blog_user:mYAw3s0meB!log@localhost:5432/blog?currentSchema=blog" do |db|
  # ... use db to perform queries
  db.using_connection do |conn|
    u = User.new "Jim"

    pp u # => #<User:0x7f7e3fe37e10 @id=nil, @name="Jim">

    em = AORM::EntityManager.new conn

    em.persist u

    em.flush

    pp u # => #<User:0x7f7e3fe37e10 @id=1, @name="Jim">
  end
end

# puts
# puts

# em.remove u

# pp em

# puts
# puts

# pp em.unit_of_work.entity_state u

# em.clear

# pp em

# # u.name = 1
