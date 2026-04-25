require "pg"
require "../src/athena-orm"

# Pipe crystal-db's statement logs to stdout in a readable form so each step's
# SQL appears inline. Source: `db` (defined as `Log = ::Log.for(self)` in
# `db.cr`; statement execution emits `"Executing query"` at debug).
::Log.setup do |c|
  backend = ::Log::IOBackend.new(STDOUT, formatter: ::Log::Formatter.new { |entry, io|
    next unless entry.source == "db"
    next unless entry.severity.debug?

    query = entry.data[:query]?
    args = entry.data[:args]?

    io << "    SQL : " << (query.try(&.as_s) || entry.message)
    if args
      io << "\tARGS: " << args
    end
  }, dispatcher: :sync)
  c.bind "db.*", :debug, backend
end

# ===== Schema =====
# Three relationship shapes get exercised:
#   - scalar columns          (User.username, Group.name, Avatar.url)
#   - OneToOne owning side    (User.avatar  -> avatars.id via users.avatar_id FK)
#   - ManyToMany              (User <-> Group via user_group join table)
# OneToMany is intentionally absent: the mapping layer has it stubbed but the UoW + persister paths aren't wired up yet, so the demo would crash.
SCHEMA = [
  "DROP TABLE IF EXISTS user_group CASCADE",
  "DROP TABLE IF EXISTS users CASCADE",
  "DROP TABLE IF EXISTS groups CASCADE",
  "DROP TABLE IF EXISTS avatars CASCADE",
  "CREATE TABLE avatars (id SERIAL PRIMARY KEY, url VARCHAR(200) NOT NULL)",
  <<-SQL,
    CREATE TABLE users (
      id        SERIAL PRIMARY KEY,
      username  VARCHAR(50) NOT NULL,
      avatar_id INTEGER REFERENCES avatars(id) ON DELETE SET NULL
    )
  SQL
  "CREATE TABLE groups (id SERIAL PRIMARY KEY, name VARCHAR(50) NOT NULL)",
  <<-SQL,
    CREATE TABLE user_group (
      user_id  INTEGER NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
      group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      PRIMARY KEY (user_id, group_id)
    )
  SQL
]

# ===== Entities =====

@[AORMA::Entity]
@[AORMA::Table(name: "avatars")]
class Avatar < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::Column(length: 200)]
  property! url : String
end

@[AORMA::Entity]
@[AORMA::Table(name: "users")]
class User < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::Column(length: 50)]
  property! username : String

  @[AORMA::OneToOne(target_entity: Avatar, cascade: ["persist"])]
  @[AORMA::JoinColumn(name: "avatar_id", referenced_column_name: "id")]
  property avatar : Avatar? = nil

  @[AORMA::ManyToMany(target_entity: Group, inversed_by: "users", cascade: ["persist"])]
  @[AORMA::JoinTable(name: "user_group")]
  @[AORMA::JoinColumn(name: "user_id", referenced_column_name: "id")]
  @[AORMA::InverseJoinColumn(name: "group_id", referenced_column_name: "id")]
  property groups : AORM::Collection(Group) = AORM::ArrayCollection(Group).new

  def add_group(group : Group) : Nil
    self.groups << group
    group.add_user self
  end
end

@[AORMA::Entity]
@[AORMA::Table(name: "groups")]
class Group < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::Column(length: 50)]
  property! name : String

  @[AORMA::ManyToMany(target_entity: User, mapped_by: "groups")]
  property users : AORM::Collection(User) = AORM::ArrayCollection(User).new

  def add_user(user : User) : Nil
    self.users << user
  end
end

# ===== Helpers =====

def step(n : Int32, title : String, &) : Nil
  puts
  puts "==> Step #{n}: #{title}"
  yield

  puts
  puts
  puts
end

def show(label : String, value) : Nil
  puts "    #{label.ljust(30)} => #{value.inspect}"
end

def expect(label : String, &) : Nil
  raise "FAIL: #{label}" unless yield
  puts "    ✓ #{label}"
end

# ===== Run =====

DB.open "postgres://blog_user:mYAw3s0meB!og@localhost:5435/postgres" do |db|
  db.using_connection do |conn|
    SCHEMA.each { |stmt| conn.exec stmt }

    em = AORM::EntityManager.new conn

    # ---------------------------------------------------------------------
    step 1, "persist + flush + post-insert ID (scalar entity)" do
      alice = User.new
      alice.username = "alice"

      show "alice.id (before)", alice.@id
      em.persist alice
      em.flush
      show "alice.id (after)", alice.id

      expect("alice got an identity-strategy id") { alice.id > 0 }
      em.clear
    end

    # ---------------------------------------------------------------------
    step 2, "find by ID + identity-map dedup" do
      first = em.find!(User, 1)
      second = em.find!(User, 1)

      show "first.username", first.username
      show "first.same_as?(second)", first.same?(second)

      expect("hydrated user has username") { first.username == "alice" }
      expect("second find hits identity map (same instance)") { first.same?(second) }
    end

    # ---------------------------------------------------------------------
    step 3, "OneToOne cascade-persist + FK column populated" do
      avatar = Avatar.new
      avatar.url = "https://example.test/bob.png"

      bob = User.new
      bob.username = "bob"
      bob.avatar = avatar

      em.persist bob
      em.flush

      show "bob.id", bob.id
      show "bob.avatar.id", bob.avatar.try(&.id)

      expect("bob got an id") { bob.id > 0 }
      expect("avatar got an id (cascade-persist)") { avatar.id > 0 }

      # Verify the FK column was populated in the user row.
      avatar_id_in_db = conn.scalar("SELECT avatar_id FROM users WHERE id = $1", bob.id).as(Int32)
      show "users.avatar_id (in DB)", avatar_id_in_db
      expect("users.avatar_id matches avatar.id") { avatar_id_in_db == avatar.id }
    end

    # ---------------------------------------------------------------------
    step 4, "cascade-persist M2M (insert into user_group)" do
      admins = Group.new
      admins.name = "admins"
      devs = Group.new
      devs.name = "devs"

      carol = User.new
      carol.username = "carol"
      carol.add_group admins
      carol.add_group devs

      em.persist carol
      em.flush

      show "carol.id", carol.id
      show "carol.groups.size", carol.groups.size
      show "admins.id", admins.id
      show "devs.id", devs.id

      join_count = conn.scalar("SELECT COUNT(*) FROM user_group WHERE user_id = $1", carol.id).as(Int64)
      show "user_group rows for carol", join_count

      expect("carol persisted with id") { carol.id > 0 }
      expect("both groups inserted via cascade") { admins.id > 0 && devs.id > 0 }
      expect("two join rows written") { join_count == 2 }
    end

    # ---------------------------------------------------------------------
    step 5, "repository find_by(criteria, order_by, limit, offset)" do
      repo = em.repository(User)
      page = repo.find_by(order_by: {"username" => "ASC"}, limit: 2, offset: 0)

      show "page.size", page.size
      show "page.map(&.username)", page.map(&.username)

      expect("limit honored") { page.size == 2 }
      expect("ordered ascending by username") { page.map(&.username) == page.map(&.username).sort }
    end

    # ---------------------------------------------------------------------
    step 6, "count" do
      repo = em.repository(User)
      total = repo.count
      show "User count", total

      expect("3 users in DB") { total == 3 }
    end

    # ---------------------------------------------------------------------
    step 7, "change tracking -> UPDATE on flush" do
      alice = em.find!(User, 1).as(User)
      show "alice.username (before)", alice.username

      alice.username = "alice_renamed"
      em.flush

      reloaded = conn.scalar("SELECT username FROM users WHERE id = $1", alice.id).as(String)
      show "alice.username (in DB)", reloaded

      expect("DB row reflects the in-memory change") { reloaded == "alice_renamed" }
    end

    # ---------------------------------------------------------------------
    step 8, "remove element from M2M collection -> join-table DELETE" do
      carol = em.find!(User, 3).as(User)

      # Force the lazy collection to load so we can mutate it.
      groups = carol.groups
      groups.size

      before = conn.scalar("SELECT COUNT(*) FROM user_group WHERE user_id = $1", carol.id).as(Int64)
      show "user_group rows (before)", before

      removed = groups.first
      groups.as(AORM::PersistentCollection(Group)).remove_element removed
      em.flush

      after = conn.scalar("SELECT COUNT(*) FROM user_group WHERE user_id = $1", carol.id).as(Int64)
      show "user_group rows (after)", after

      expect("one join row deleted") { after == before - 1 }
    end

    # ---------------------------------------------------------------------
    step 9, "remove entity -> DELETE row + cascade join cleanup" do
      carol = em.find!(User, 3).as(User)
      em.remove carol
      em.flush

      remaining = conn.scalar("SELECT COUNT(*) FROM users WHERE id = $1", 3).as(Int64)
      join_remaining = conn.scalar("SELECT COUNT(*) FROM user_group WHERE user_id = $1", 3).as(Int64)
      show "users rows for carol", remaining
      show "user_group rows for carol", join_remaining

      expect("user row gone") { remaining == 0 }
      expect("join rows cleaned via FK CASCADE") { join_remaining == 0 }
    end

    em.close
  end
end

puts
puts "All steps passed."
