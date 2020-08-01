require "db"

require "./sequence_generator"
require "./value_generation_plan_interface"
require "./value_generation_executor_interface"
require "./column_value_generator_executor"
require "./single_value_generation_plan"

require "./cached_persister_context"

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

class DB::Connection
  def database_platform
    AORM::Platforms::Postgres.new
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

  @[AORM::Column]
  property alive : Bool = true
end

class Post < AORM::Entity
end

require "pg"

DB.open "postgres://blog_user:mYAw3s0meB!log@localhost:5432/blog?currentSchema=blog" do |db|
  # ... use db to perform queries
  db.using_connection do |conn|
    u1 = User.new "Jim"
    u2 = User.new "Sally"

    em = AORM::EntityManager.new conn

    pp em.find User, 1 # => #<User:0x7fc5f30aacc0 @alive=true, @id=1, @name="Jim">

    # em.persist u1
    # em.persist u2

    # em.flush
    # puts

    # em.remove u2
    # u1.name = "Bob"
    # u1.alive = false

    # em.flush
    # puts

    # u1.name = "Fred"

    # em.flush
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
