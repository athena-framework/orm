require "pg"

require "./annotations/*"
require "./mapping/annotations"
require "./mapping/*"
require "./persisters/entity/*"
require "./platforms/*"
require "./sequencing/executors/*"
require "./sequencing/generators/*"
require "./sequencing/planning/*"
require "./types/*"

require "./default_repository_factory"
require "./entity"
require "./entity_manager"
require "./entity_repository"
require "./unit_of_work"

# Convenience alias to make referencing `Athena::ORM` types easier.
alias AORM = Athena::ORM

alias AORMA = Athena::ORM::Annotations

module Athena::ORM
  VERSION = "0.1.0"

  enum LockMode
    None
  end
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

  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  getter! id : Int64

  @[AORMA::Column]
  property name : String

  @[AORMA::Column]
  property alive : Bool = true
end

class Post < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  getter! id : Int64
end

require "pg"

DB.open "postgres://blog_user:mYAw3s0meB!log@localhost:5432/blog?currentSchema=blog" do |db|
  db.using_connection do |conn|
    em = AORM::EntityManager.new conn

    # repo = em.repository User

    # pp User.entity_class_metadata

    # pp repo.find 123

    # pp repo.find_by alive: false

    # pp repo.find_one_by id: 3
    # pp repo.find_one_by id: 4

    # pp repo.count alive: false

    # repo2 = em.repository Post

    # pp repo2.find 2

    u1 = User.new "Jim"
    u2 = User.new "Sally"

    em = AORM::EntityManager.new conn

    em.persist u1
    em.persist u2

    em.flush
    puts

    em.remove u2
    u1.name = "Bob"
    u1.alive = false

    em.flush
    puts

    u1.name = "Fred"

    em.flush
  end
end
