require "db"

require "./annotations/*"
require "./collection/*"
require "./exceptions/*"
require "./internal/**"
require "./id/*"
require "./mapping/annotations"
require "./mapping/**"
require "./persisters/entity/*"
require "./persisters/collection/*"
require "./platforms/*"
require "./query/*"
require "./sql/parser"
require "./types/*"
require "./utility/*"

require "./connection"
require "./default_repository_factory"
require "./entity"
require "./entity_manager"
require "./entity_repository"
require "./native_query"
require "./persister_helper"
require "./unit_of_work"

require "./ext/db"

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

# ## ManyToMany Association Example
#
# ### SQL Schema
#
# ```sql
# CREATE TABLE users (
#     id SERIAL PRIMARY KEY,
#     username VARCHAR(50) NOT NULL
# );
#
# CREATE TABLE groups (
#     id SERIAL PRIMARY KEY,
#     name VARCHAR(50) NOT NULL
# );
#
# -- Join table for the ManyToMany relationship
# CREATE TABLE user_group (
#     user_id INTEGER NOT NULL REFERENCES users(id),
#     group_id INTEGER NOT NULL REFERENCES groups(id),
#     PRIMARY KEY (user_id, group_id)
# );
# ```
#
# ### Entity Definitions
#

# The User entity - owns the ManyToMany relationship
@[AORMA::Entity]
@[AORMA::Table(name: "users")]
class User < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::Column(length: 50)]
  property! username : String

  # Owning side: has inversed_by pointing to the inverse side's field
  @[AORMA::ManyToMany(target_entity: Group, inversed_by: "users", cascade: ["persist"], fetch_mode: :eager)]
  property groups : AORM::Collection(Group) = AORM::ArrayCollection(Group).new
end

# The Group entity - inverse side of the relationship
@[AORMA::Entity]
@[AORMA::Table(name: "groups")]
class Group < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::Column(length: 50)]
  property! name : String

  # # Inverse side: has mapped_by pointing to the owning side's field
  # @[AORMA::ManyToMany(target_entity: User, mapped_by: "groups")]
  # property users : AORM::Collection(User) = AORM::ArrayCollection(User).new
end

# # ## Custom Join Table and Column Names

# @[AORMA::Entity]
# class Tag < AORM::Entity
#   @[AORMA::Column]
#   @[AORMA::ID]
#   @[AORMA::GeneratedValue]
#   property! id : Int32

#   @[AORMA::Column(length: 50)]
#   property! name : String
# end

# @[AORMA::Entity]
# class Article < AORM::Entity
#   @[AORMA::Column]
#   @[AORMA::ID]
#   @[AORMA::GeneratedValue]
#   property! id : Int32

#   # Custom join table name and column names
#   @[AORMA::ManyToMany(target_entity: Tag, cascade: ["persist"])]
#   @[AORMA::JoinTable(name: "article_tags")]
#   @[AORMA::JoinColumn(name: "article_id", referenced_column_name: "id")]
#   @[AORMA::InverseJoinColumn(name: "tag_id", referenced_column_name: "id")]
#   property tags : AORM::PersistentCollection(Tag) = AORM::PersistentCollection(Tag).new
# end

require "pg"

# connection = DB.connect "postgres://blog_user:mYAw3s0meB!og@localhost:5435/postgres"
# em = AORM::EntityManager.new connection

# # Create entities
# user = User.new
# user.username = "alice"

# group1 = Group.new
# group1.name = "Admins"

# group2 = Group.new
# group2.name = "Users"

# # Add groups to user's collection (owning side)
# user.groups << group1
# user.groups << group2

# # Persist and flush - cascade: ["persist"] saves groups automatically
# em.persist(user)

# em.flush

# # Later: load user with groups

# # SELECT t0.id AS id_1, t0.username AS username_2 FROM users t0 WHERE t0.id = $1
# loaded_user = em.find!(User, 1)
# loaded_group = em.find! Group, 1

# loaded_user.groups[1].name = "Super Admin"
# loaded_user.groups.delete loaded_group

# pp loaded_user.groups.map &.name

# em.flush
