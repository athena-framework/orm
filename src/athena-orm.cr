require "pg"

require "./annotations/*"
require "./exceptions/*"
require "./mapping/annotations"
require "./mapping/property"
require "./mapping/*"
require "./hydrators/*"
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

  enum HydrationMode
    Object
    SimpleObject
  end
end

class PG::Driver
  def database_platform
    AORM::Platforms::Postgres.new
  end
end

class DB::Database
  def database_platform
    @driver.database_platform
  end
end

# enum Test
#   One
#   Two
# end

# struct TestEnumType < Athena::ORM::Types::Enum(Test); end

# AORM::Types::Type.add_type TestEnumType, TestEnumType

# class Post < AORM::Entity
# @[AORMA::Column]
# @[AORMA::ID]
# @[AORMA::GeneratedValue]
# getter! id : Int64

#   @[AORMA::OneToOne(inversed_by: "post")]
#   getter! user : User
# end

@[AORMA::Table(name: "settings")]
class Setting < AORM::Entity
  def initialize(@color : String); end

  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  getter! id : Int64

  @[AORMA::Column]
  property color : String

  # @[AORMA::OneToOne(inversed_by: "setting")]
  # property! user : User
end

@[AORMA::Entity(repository_class: UserRepository)]
@[AORMA::Table(name: "users")]
class User < AORM::Entity
  def initialize(@name : String); end

  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  getter! id : Int64

  @[AORMA::Column]
  property name : String

  @[AORMA::Column]
  property alive : Bool = true

  # @[AORMA::OneToOne(mapped_by: "user")]
  # property! setting : Setting
end

require "pg"

class UserRepository < AORM::EntityRepository(User)
  def active_users
    self.find_by(alive: true)
  end

  def primary_user : User
    self.find(4)
  end
end

# DB.open "postgres://blog_user:mYAw3s0meB!log@localhost:5432/blog?currentSchema=blog" do |db|
# db.using_connection do |conn|
em = AORM::EntityManager.new "postgres://blog_user:mYAw3s0meB!log@localhost:5432/blog?currentSchema=blog"

# pp em.class_metadata User
# pp em.class_metadata Setting
# u = em.find User, 2
# s = em.find Setting, 1

# pp typeof(u)
# pp typeof(s)

# u = em.find! User, 2
# s = em.find! Setting, 1

# pp typeof(u)
# pp typeof(s)

# u.not_nil!.alive = false

# pp u

# em.flush

# pp u
# pp em.find User, 1
# pp em.find User, 1
# pp em.find User, 1

repo = em.repository User

pp typeof(repo)

u = repo.find 1
u2 = repo.find! 1

pp typeof(u)
pp typeof(u2)

# repo_find = repo.find 1
# repo_find = repo.find 1
# repo_find = repo.find 1
# repo_find = repo.find 1

# pp repo_find, typeof(repo_find)

# puts

# active_users = repo.active_users
# pp active_users, typeof(active_users)

# puts

# active_users = repo.active_users
# pp active_users, typeof(active_users)

# puts

# primary_user = repo.primary_user
# pp primary_user, typeof(primary_user)

# pp repo.find 1
# pp repo.find 123

# pp repo.find_by id: 1, alive: true
# pp repo.find_by id: [1, 3, 5, nil], alive: false

# pp repo.find_one_by id: 3
# pp repo.find_one_by id: 4

# pp repo.count alive: false

# repo2 = em.repository Post

# pp repo2.find 2

# u1 = User.new "Jim"
#   u2 = User.new "Sally"

#   em = AORM::EntityManager.new conn

# em.persist u1
#   em.persist u2

# em.flush
#   puts

#   em.remove u2
#   u1.name = "Bob"
#   u1.alive = false

#   em.flush
#   puts

#   u1.name = "Fred"

#   em.flush
# end
# end
