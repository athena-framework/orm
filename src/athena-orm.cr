require "db"

require "./metadata/*"
require "./platforms/*"
require "./types/*"

require "./entity_manager"
require "./model"

# Convenience alias to make referencing `Athena::ORM` types easier.
alias AORM = Athena::ORM

module Athena::ORM
  VERSION = "0.1.0"

  annotation Column; end
  annotation ID; end
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
  getter! id : Int64

  @[AORM::Column]
  property name : String

  # @[AORM::Column]
  # property? admin : Bool = false

  # @[AORM::Column(type: TestEnumType)]
  # property test : Test
end

# rs = FieldEmitter.new.tap do |e|
#   e._set_values([1_i64, "Jim"])
# end

# u = User.from_rs rs

u = User.new "Jim"

pp u

em = AORM::EntityManager.new FakeConnection.new

em.persist u

pp em

puts
puts

em.remove u

pp em

puts
puts

pp em.unit_of_work.entity_state u

em.clear

pp em

# u.name = 1
