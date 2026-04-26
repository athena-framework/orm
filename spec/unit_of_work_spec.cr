require "./spec_helper"
require "uuid"

# Inline test entities — kept here rather than under spec/models/ because they
# only matter to this file's coverage of UnitOfWork edge cases.
@[AORMA::Entity]
class VersionedAssignedIdentifierEntity < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  property! id : Int32
  # @[AORMA::Version] not implemented
  property version : Int32 = 0
end

@[AORMA::Entity]
class EntityWithStringIdentifier < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property id : String? = nil
end

@[AORMA::Entity]
class EntityWithBooleanIdentifier < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property id : Bool? = nil
end

@[AORMA::Entity]
class EntityWithCompositeStringIdentifier < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property id1 : String? = nil
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property id2 : String? = nil
end

@[AORMA::Entity]
class CascadePersistedEntity < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property id : String? = nil

  def initialize
    @id = "#{self.class.name}-#{UUID.random}"
  end
end

@[AORMA::Entity]
class EntityWithCascadingAssociation < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property id : String? = nil

  @[AORMA::OneToOne(target_entity: CascadePersistedEntity, cascade: ["persist"])]
  @[AORMA::JoinColumn(name: "cascaded_id", referenced_column_id: "id")]
  property cascaded : CascadePersistedEntity? = nil

  def initialize
    @id = "#{self.class.name}-#{UUID.random}"
  end
end

@[AORMA::Entity]
class EntityWithNonCascadingAssociation < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property id : String? = nil

  @[AORMA::OneToOne(target_entity: CascadePersistedEntity)]
  @[AORMA::JoinColumn(name: "non_cascaded_id", referenced_column_id: "id")]
  property non_cascaded : CascadePersistedEntity? = nil

  def initialize
    @id = "#{self.class.name}-#{UUID.random}"
  end
end

@[AORMA::Entity]
class TaggedItem < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::Column]
  property! name : String
end

@[AORMA::Entity]
class TagOwner < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::ManyToMany(target_entity: TaggedItem, index_by: "name", cascade: ["persist"])]
  property tags : AORM::PersistentCollection(TaggedItem) = AORM::PersistentCollection(TaggedItem).new
end

@[AORMA::Entity]
class CustomJoinProduct < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32
end

@[AORMA::Entity]
class CustomJoinCategory < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::ManyToMany(target_entity: CustomJoinProduct, cascade: ["persist"])]
  @[AORMA::JoinTable(name: "my_custom_join_table")]
  property products : AORM::PersistentCollection(CustomJoinProduct) = AORM::PersistentCollection(CustomJoinProduct).new
end

# Test entity with fully custom join columns
@[AORMA::Entity]
class CustomColumnProduct < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32
end

@[AORMA::Entity]
class CustomColumnCategory < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::ManyToMany(target_entity: CustomColumnProduct, cascade: ["persist"])]
  @[AORMA::JoinTable(name: "category_product_map")]
  @[AORMA::JoinColumn(name: "cat_id", referenced_column_name: "id")]
  @[AORMA::InverseJoinColumn(name: "prod_id", referenced_column_name: "id")]
  property products : AORM::PersistentCollection(CustomColumnProduct) = AORM::PersistentCollection(CustomColumnProduct).new
end

# Fixtures: a User has many Posts (OneToMany inverse) backed by a Post that belongs to a User (ManyToOne owning).
# Used to exercise OneToMany lazy load, metadata, and cascade-persist.
# Fixtures: ToOne owning sides that explicitly override the join-column name
# via @[AORMA::JoinColumn], to verify the annotation flows through the driver
# rather than being silently dropped.
@[AORMA::Entity]
class CustomJoinTarget < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32
end

@[AORMA::Entity]
class CustomJoinOwner < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::OneToOne]
  @[AORMA::JoinColumn(name: "explicit_one_to_one_fk", referenced_column_name: "id")]
  property linked : CustomJoinTarget? = nil

  @[AORMA::ManyToOne]
  @[AORMA::JoinColumn(name: "explicit_many_to_one_fk", referenced_column_name: "id")]
  property parent : CustomJoinTarget? = nil
end

@[AORMA::Entity]
@[AORMA::Table(name: "blog_users")]
class BlogUser < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::Column]
  property! username : String

  @[AORMA::OneToMany(mapped_by: "user", cascade: ["persist"])]
  property posts : AORM::Collection(BlogPost) = AORM::ArrayCollection(BlogPost).new
end

@[AORMA::Entity]
@[AORMA::Table(name: "blog_posts")]
class BlogPost < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::Column]
  property! title : String

  @[AORMA::ManyToOne(inversed_by: "posts")]
  property user : BlogUser? = nil
end

# Stand-in persister that mimics the hydrator's `:collection`-hint behavior:
# when `load_many_to_many_collection` runs, the canned entities are pushed
# directly into the target collection via `hydrate_add`. Used to verify that
# the UoW doesn't add them a second time on top of that.
class CollectionAddingPersister < AORM::Persisters::Entity::Basic
  property canned_entities : Array(AORM::Entity) = [] of AORM::Entity

  def load_many_to_many_collection(
    assoc : AORM::Mapping::ManyToMany,
    source_entity : AORM::Entity,
    collection : AORM::PersistentCollection,
  ) : Array
    @canned_entities.each { |e| collection.hydrate_add e }
    @canned_entities
  end
end

# Fixtures: associations declared without `target_entity` so the inference
# from the property's type restriction is what gets exercised.
@[AORMA::Entity]
class InferredTargetTag < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32
end

@[AORMA::Entity]
class InferredTargetOwner < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  # Inferred from `InferredTargetTag?`
  @[AORMA::OneToOne]
  property primary : InferredTargetTag? = nil

  # Inferred from `AORM::Collection(InferredTargetTag)`
  @[AORMA::ManyToMany]
  property tags : AORM::Collection(InferredTargetTag) = AORM::ArrayCollection(InferredTargetTag).new
end

struct UnitOfWorkTest < ASPEC::TestCase
  @connection : MockConnection
  @em : MockEntityManager
  @uow : MockUnitOfWork

  def initialize
    @connection = MockConnection.new
    @connection.push_ids Int32, 1, 2, 3, 4, 5, 6
    @em = MockEntityManager.new @connection
    @uow = MockUnitOfWork.new @em
    @em.uow_mock = @uow
  end

  def test_register_removed_on_new_entity_is_ignored : Nil
    user = ForumUser.new
    user.username = "Fred"
    @uow.is_scheduled_for_delete?(user).should be_false
    @uow.schedule_for_delete user
    @uow.is_scheduled_for_delete?(user).should be_false
  end

  def test_saving_single_entity_with_identity_column_forces_insert : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata ForumUser
    @uow.set_entity_persister ForumUser, user_persister
    user_persister.mock_id_generator = :identity

    user = ForumUser.new
    user.username = "Fred"
    @uow.persist user

    user_persister.inserts.size.should eq 0
    user_persister.updates.size.should eq 0
    user_persister.deletes.size.should eq 0
    @uow.is_in_identity_map(user).should be_false
    @uow.is_scheduled_for_insert?(user).should be_true

    user_persister.reset

    @uow.commit
    user_persister.inserts.size.should eq 1
    user_persister.updates.size.should eq 0
    user_persister.deletes.size.should eq 0

    user.id.should be_a Int32
  end

  def test_multiple_inserts_are_batched_in_the_persister : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata Country
    @uow.set_entity_persister Country, user_persister

    country1 = Country.new
    country1.country = "Italy"
    country2 = Country.new
    country2.country = "Germany"

    @uow.persist country1
    @uow.persist country2
    @uow.commit

    user_persister.inserts.size.should eq 2
    user_persister.execute_insert_call_count.should eq 1
  end

  def test_cascaded_identity_column_insert : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata ForumUser
    @uow.set_entity_persister ForumUser, user_persister
    user_persister.mock_id_generator = :identity

    avatar_persister = MockEntityPersister.new @em, @em.class_metadata ForumUser
    @uow.set_entity_persister ForumAvatar, avatar_persister
    avatar_persister.mock_id_generator = :identity

    user = ForumUser.new
    user.username = "Fred"
    avatar = ForumAvatar.new
    user.avatar = avatar
    @uow.persist user
    @uow.commit

    user.id.is_a? Number
    avatar.id.is_a? Number

    user_persister.inserts.size.should eq 1
    user_persister.updates.size.should eq 0
    user_persister.deletes.size.should eq 0

    avatar_persister.inserts.size.should eq 1
    avatar_persister.updates.size.should eq 0
    avatar_persister.deletes.size.should eq 0
  end

  def test_load_collection_does_not_double_add_hydrated_entities : Nil
    # The persister's `load_many_to_many_collection` already adds the loaded
    # entities into the target collection (via the `:collection` hydrator hint).
    # `UnitOfWork#load_collection` must not re-add them on top of that, or the
    # collection ends up with each row twice.
    user_persister = MockEntityPersister.new @em, @em.class_metadata CmsUser
    @uow.set_entity_persister CmsUser, user_persister

    group_persister = CollectionAddingPersister.new @em, @em.class_metadata(CmsGroup)
    @uow.set_entity_persister CmsGroup, group_persister
    group_persister.canned_entities = [build_cms_group(1, "admins"), build_cms_group(2, "devs")] of AORM::Entity

    data = Hash(String, AORM::Mapping::Value).new
    data["id"] = AORM::Mapping::SingleValue(Int32).new(7)
    data["username"] = AORM::Mapping::SingleValue(String).new("fred")
    user = @uow.create_entity(CmsUser, data).as CmsUser
    pc = user.groups.as(AORM::PersistentCollection(CmsGroup))

    @uow.load_collection pc

    pc.size.should eq 2
    pc.loaded?.should be_true
  end

  private def build_cms_group(id : Int32, name : String) : CmsGroup
    g = CmsGroup.new
    g.name = name
    pointerof(g.@id).value = id
    g
  end

  def test_compute_change_set_does_not_initialize_unchanged_lazy_collection : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata CmsUser
    @uow.set_entity_persister CmsUser, user_persister

    # Drive the hydration path so the user gets an injected (uninitialized)
    # PersistentCollection for `groups`, the same as a real `find!` would.
    data = Hash(String, AORM::Mapping::Value).new
    data["id"] = AORM::Mapping::SingleValue(Int32).new(1)
    data["username"] = AORM::Mapping::SingleValue(String).new("fred")
    user = @uow.create_entity(CmsUser, data).as CmsUser
    pc = user.groups.as(AORM::PersistentCollection(CmsGroup))
    pc.loaded?.should be_false

    # Modify a scalar field and commit. The lazy groups collection must NOT be
    # initialized as a side effect of computing the user's changeset.
    user.username = "fred-renamed"
    @uow.commit

    pc.loaded?.should be_false
  end

  def test_schedule_extra_update_merges_repeated_changesets : Nil
    user = ForumUser.new
    user.username = "fred"

    avatar1 = ForumAvatar.new
    avatar2 = ForumAvatar.new
    val1 = AORM::Mapping::SingleValue(AORM::Entity?).new(avatar1)
    val2 = AORM::Mapping::SingleValue(AORM::Entity?).new(avatar2)

    @uow.schedule_extra_update user, {"avatar" => AORM::UnitOfWork::Change.new(nil, val1)}
    @uow.schedule_extra_update user, {"username" => AORM::UnitOfWork::Change.new(nil, val2)}

    extras = @uow.extra_update_for user
    extras.keys.sort.should eq ["avatar", "username"]
  end

  def test_execute_extra_updates_runs_persister_update_with_patched_changeset : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata ForumUser
    @uow.set_entity_persister ForumUser, user_persister
    user_persister.mock_id_generator = :identity

    avatar_persister = MockEntityPersister.new @em, @em.class_metadata ForumAvatar
    @uow.set_entity_persister ForumAvatar, avatar_persister
    avatar_persister.mock_id_generator = :identity

    avatar = ForumAvatar.new
    user = ForumUser.new
    user.username = "fred"
    user.avatar = avatar

    # The cycle-style write would normally be wired via a persister, but here we
    # poke the UoW directly to verify the update fires after the main inserts.
    @uow.persist user
    avatar_value = AORM::Mapping::SingleValue(AORM::Entity?).new(avatar)
    @uow.schedule_extra_update user, {"avatar" => AORM::UnitOfWork::Change.new(nil, avatar_value)}

    @uow.commit

    user_persister.updates.size.should eq 1
    user_persister.updates.first.should be user
    @uow.extra_update_for(user).should be_empty
  end

  def test_insert_execution_order_places_to_one_owning_side_target_first : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata ForumUser
    @uow.set_entity_persister ForumUser, user_persister
    user_persister.mock_id_generator = :identity

    avatar_persister = MockEntityPersister.new @em, @em.class_metadata ForumAvatar
    @uow.set_entity_persister ForumAvatar, avatar_persister
    avatar_persister.mock_id_generator = :identity

    user = ForumUser.new
    user.username = "Fred"
    avatar = ForumAvatar.new
    user.avatar = avatar

    # Persisting the user cascades into the avatar; the user gets registered
    # for insert first, but the FK on users -> avatars means the topological
    # sort must place the avatar ahead of the user in the execution order.
    @uow.persist user
    @uow.compute_changesets

    order = @uow.insert_execution_order

    order.index(avatar).should_not be_nil
    order.index(user).should_not be_nil
    order.index(avatar).not_nil!.should be < order.index(user).not_nil!
  end

  @[Pending]
  def test_get_entity_state_on_versioned_entity_with_assigned_identifier : Nil
    # Requires: @[AORMA::Version] annotation support
  end

  def test_get_entity_state_with_assigned_identity : Nil
    persister = MockEntityPersister.new @em, @em.class_metadata CmsPhonenumber
    @uow.set_entity_persister CmsPhonenumber, persister

    ph = CmsPhonenumber.new
    ph.phonenumber = "12345"

    @uow.entity_state(ph).should eq AORM::UnitOfWork::EntityState::New
    persister.exists_called?.should be_true

    persister.reset

    # exists check should be skipped if entity is already managed
    @uow.register_managed ph, {"phonenumber" => "12345"}, {} of String => NoReturn
    @uow.entity_state(ph).should eq AORM::UnitOfWork::EntityState::Managed
    persister.exists_called?.should be_false

    ph2 = CmsPhonenumber.new
    ph2.phonenumber = "12345"
    @uow.entity_state(ph2).should eq AORM::UnitOfWork::EntityState::Detached
    persister.exists_called?.should be_false
  end

  def test_no_undefined_index_notice_on_schedule_for_update_without_changes : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata ForumUser
    @uow.set_entity_persister ForumUser, user_persister
    user_persister.mock_id_generator = :identity

    user = ForumUser.new
    user.username = "Fred"
    @uow.persist user
    @uow.commit

    # Schedule for update without changes
    @uow.schedule_for_update user
    @uow.scheduled_entity_updates.should_not be_empty
    @uow.commit
    @uow.scheduled_entity_updates.should be_empty
  end

  def test_removed_and_re_persisted_entities_are_in_the_identity_map : Nil
    phonenumber_persister = MockEntityPersister.new @em, @em.class_metadata CmsPhonenumber
    @uow.set_entity_persister CmsPhonenumber, phonenumber_persister

    phone = CmsPhonenumber.new
    phone.phonenumber = "123456"

    @uow.persist phone
    @uow.commit

    @uow.is_in_identity_map(phone).should be_true

    @uow.schedule_for_delete phone
    @uow.is_in_identity_map(phone).should be_false

    @uow.persist phone
    @uow.is_in_identity_map(phone).should be_true
  end

  @[DataProvider("entities_with_valid_identifiers_provider")]
  def test_add_to_identity_map_valid_identifiers(entity : AORM::Entity, id_hash : String) : Nil
    @uow.persist entity
    @uow.add_to_identity_map entity

    @uow.get_by_id_hash(id_hash, entity.class).should be entity
  end

  def entities_with_valid_identifiers_provider : Hash
    empty_string = EntityWithStringIdentifier.new
    empty_string.id = ""

    non_empty_string = EntityWithStringIdentifier.new
    non_empty_string.id = "test-id-123"

    bool_true = EntityWithBooleanIdentifier.new
    bool_true.id = true

    bool_false = EntityWithBooleanIdentifier.new
    bool_false.id = false

    {
      "empty string, single field"     => {empty_string, ""},
      "non-empty string, single field" => {non_empty_string, "test-id-123"},
      # # two fields
      "boolean true"  => {bool_true, "1"},
      "boolean false" => {bool_false, ""},
    }
  end

  def test_registering_a_managed_instance_requires_a_non_empty_identifier : Nil
    entity = EntityWithStringIdentifier.new
    entity.id = nil

    expect_raises(Exception, "entity without identity") do
      @uow.register_managed entity, {} of String => AORM::Mapping::Value, {} of String => AORM::Mapping::Value
    end
  end

  @[DataProvider("entities_with_invalid_identifiers_provider")]
  def test_add_to_identity_map_invalid_identifiers(entity : AORM::Entity, id : Hash(String, AORM::Mapping::Value)) : Nil
    expect_raises(Exception) do
      @uow.register_managed entity, id, {} of String => AORM::Mapping::Value
    end
  end

  def entities_with_invalid_identifiers_provider : Hash
    {
      "nil string" => {
        EntityWithStringIdentifier.new,
        {"id" => AORM::Mapping::ColumnValue(String?).new("id", nil).as(AORM::Mapping::Value)},
      },
      "composite, both nil" => {
        EntityWithCompositeStringIdentifier.new,
        {
          "id1" => AORM::Mapping::ColumnValue(String?).new("id1", nil).as(AORM::Mapping::Value),
          "id2" => AORM::Mapping::ColumnValue(String?).new("id2", nil).as(AORM::Mapping::Value),
        },
      },
      "composite, first field nil" => {
        EntityWithCompositeStringIdentifier.new,
        {
          "id1" => AORM::Mapping::ColumnValue(String?).new("id1", nil).as(AORM::Mapping::Value),
          "id2" => AORM::Mapping::ColumnValue(String?).new("id2", "bar").as(AORM::Mapping::Value),
        },
      },
      "composite, second field nil" => {
        EntityWithCompositeStringIdentifier.new,
        {
          "id1" => AORM::Mapping::ColumnValue(String?).new("id1", "foo").as(AORM::Mapping::Value),
          "id2" => AORM::Mapping::ColumnValue(String?).new("id2", nil).as(AORM::Mapping::Value),
        },
      },
    }
  end

  def test_new_associated_entity_persistence_through_cascaded_associations_first : Nil
    persister1 = MockEntityPersister.new @em, @em.class_metadata CascadePersistedEntity
    persister2 = MockEntityPersister.new @em, @em.class_metadata EntityWithCascadingAssociation
    persister3 = MockEntityPersister.new @em, @em.class_metadata EntityWithNonCascadingAssociation
    @uow.set_entity_persister CascadePersistedEntity, persister1
    @uow.set_entity_persister EntityWithCascadingAssociation, persister2
    @uow.set_entity_persister EntityWithNonCascadingAssociation, persister3

    cascade_persisted = CascadePersistedEntity.new
    cascading = EntityWithCascadingAssociation.new
    non_cascading = EntityWithNonCascadingAssociation.new

    # Both entities reference the same CascadePersistedEntity.
    # EntityWithCascadingAssociation has cascade: ["persist"], so persisting it
    # will also persist CascadePersistedEntity. EntityWithNonCascadingAssociation
    # does not have cascade, but since CascadePersistedEntity gets persisted
    # through the other path, no error should occur.
    cascading.cascaded = cascade_persisted
    non_cascading.non_cascaded = cascade_persisted

    @uow.persist cascading
    @uow.persist non_cascading

    @uow.commit

    persister1.inserts.size.should eq 1
    persister2.inserts.size.should eq 1
    persister3.inserts.size.should eq 1
  end

  def test_new_associated_entity_persistence_through_non_cascaded_associations_first : Nil
    persister1 = MockEntityPersister.new @em, @em.class_metadata CascadePersistedEntity
    persister2 = MockEntityPersister.new @em, @em.class_metadata EntityWithCascadingAssociation
    persister3 = MockEntityPersister.new @em, @em.class_metadata EntityWithNonCascadingAssociation
    @uow.set_entity_persister CascadePersistedEntity, persister1
    @uow.set_entity_persister EntityWithCascadingAssociation, persister2
    @uow.set_entity_persister EntityWithNonCascadingAssociation, persister3

    cascade_persisted = CascadePersistedEntity.new
    cascading = EntityWithCascadingAssociation.new
    non_cascading = EntityWithNonCascadingAssociation.new

    # First persist and flush EntityWithCascadingAssociation with the cascading
    # association not set. Having the "cascading path" involve a non-new object
    # is important to show that the ORM should be considering cascades across
    # entity changesets in subsequent flushes.
    cascading.cascaded = nil

    @uow.persist cascading
    @uow.commit

    persister1.inserts.size.should eq 0
    persister2.inserts.size.should eq 1
    persister3.inserts.size.should eq 0

    # Note that we have NOT directly persisted the CascadePersistedEntity,
    # and EntityWithNonCascadingAssociation does NOT have a configured
    # cascade-persist.
    non_cascading.non_cascaded = cascade_persisted

    # However, EntityWithCascadingAssociation *does* have a cascade-persist
    # association, which ought to allow us to save the CascadePersistedEntity
    # anyway through that connection.
    cascading.cascaded = cascade_persisted

    @uow.persist non_cascading
    @uow.commit

    persister1.inserts.size.should eq 1
    persister2.inserts.size.should eq 1
    persister3.inserts.size.should eq 1
  end

  def test_previous_detected_illegal_new_non_cascaded_entities_are_cleaned_up : Nil
    persister1 = MockEntityPersister.new @em, @em.class_metadata CascadePersistedEntity
    persister2 = MockEntityPersister.new @em, @em.class_metadata EntityWithNonCascadingAssociation
    @uow.set_entity_persister CascadePersistedEntity, persister1
    @uow.set_entity_persister EntityWithNonCascadingAssociation, persister2

    cascade_persisted = CascadePersistedEntity.new
    non_cascading = EntityWithNonCascadingAssociation.new

    # We explicitly cause the ORM to detect a non-persisted new entity in the
    # association graph (non_cascaded has no cascade: ["persist"])
    non_cascading.non_cascaded = cascade_persisted

    @uow.persist non_cascading

    expect_raises(Exception, "new entities found through relationships") do
      @uow.commit
    end

    persister1.inserts.should be_empty
    persister2.inserts.should be_empty

    @uow.clear
    @uow.persist CascadePersistedEntity.new
    @uow.commit

    # Persistence operations should just recover normally
    persister1.inserts.size.should eq 1
    persister2.inserts.size.should eq 0
  end

  @[Pending]
  def test_commit_throw_optimistic_lock_exception_when_connection_commit_fails : Nil
    # Requires: OptimisticLockException
  end

  def test_it_throws_when_looking_up_identifier_for_unknown_entity : Nil
    # Use an entity that hasn't been tracked by the UnitOfWork
    unknown_entity = EntityWithStringIdentifier.new
    unknown_entity.id = "test"

    expect_raises(Exception, /Unable to find.*entity identifier associated with the UnitOfWork/) do
      @uow.entity_identifier unknown_entity
    end
  end

  def test_removed_entity_is_removed_from_many_to_many_collection : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata CmsUser
    @uow.set_entity_persister CmsUser, user_persister
    user_persister.mock_id_generator = :identity

    group_persister = MockEntityPersister.new @em, @em.class_metadata CmsGroup
    @uow.set_entity_persister CmsGroup, group_persister
    group_persister.mock_id_generator = :identity

    user = CmsUser.new
    user.username = "test_user"

    group1 = CmsGroup.new
    group1.name = "group1"

    group2 = CmsGroup.new
    group2.name = "group2"

    user.groups << group1
    user.groups << group2

    @uow.persist user
    @uow.commit

    user_persister.inserts.size.should eq 1
    group_persister.inserts.size.should eq 2

    user.id.should_not be_nil
    group1.id.should_not be_nil
    group2.id.should_not be_nil

    # Take a snapshot of the collection state after persist.
    # The UoW promotes user.groups to a PersistentCollection during commit,
    # so the runtime type matches even though the property is declared as Collection.
    user.groups.as(AORM::PersistentCollection(CmsGroup)).take_snapshot

    # Verify both groups are in the collection
    user.groups.size.should eq 2
    user.groups.includes?(group1).should be_true
    user.groups.includes?(group2).should be_true

    # The UoW defers the in-memory collection cleanup until after `commit`
    # succeeds, so the assertion has to come after the next flush.
    @uow.remove group1
    @uow.commit

    user.groups.includes?(group1).should be_false
    user.groups.size.should eq 1
    user.groups.includes?(group2).should be_true
  end

  def test_removed_entity_is_removed_from_one_to_many_collection : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata BlogUser
    @uow.set_entity_persister BlogUser, user_persister
    user_persister.mock_id_generator = :identity

    post_persister = MockEntityPersister.new @em, @em.class_metadata BlogPost
    @uow.set_entity_persister BlogPost, post_persister
    post_persister.mock_id_generator = :identity

    user = BlogUser.new
    user.username = "fred"
    p1 = BlogPost.new
    p1.title = "first"
    p2 = BlogPost.new
    p2.title = "second"
    user.posts << p1
    user.posts << p2

    @uow.persist user
    @uow.commit

    # Now remove p1 and re-flush — it should be marked for delete AND dropped
    # from user.posts (via pending_collection_element_removals applied on commit).
    @uow.remove p1
    @uow.commit

    user.posts.size.should eq 1
    user.posts.includes?(p2).should be_true
    user.posts.includes?(p1).should be_false
  end

  def test_it_throws_when_application_provided_ids_collide : Nil
    entity1 = EntityWithStringIdentifier.new
    entity1.id = "same-id"

    entity2 = EntityWithStringIdentifier.new
    entity2.id = "same-id"

    @uow.persist entity1
    # For entities with assigned IDs, persist automatically adds to identity map

    # Persisting entity2 with same ID should throw collision error
    expect_raises(Exception, "entity identity collision") do
      @uow.persist entity2
    end
  end

  def test_it_preserves_the_original_exception_on_rollback_failure : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata ForumUser
    @uow.set_entity_persister ForumUser, user_persister
    user_persister.mock_id_generator = :identity

    user = ForumUser.new
    user.username = "Fred"
    @uow.persist user

    # Mock an exception during insert by using a persister that throws
    failing_persister = FailingEntityPersister.new @em, @em.class_metadata(ForumUser), "Insert failed"
    @uow.set_entity_persister ForumUser, failing_persister

    expect_raises(Exception, "Insert failed") do
      @uow.commit
    end
  end

  def test_refresh_updates_managed_entity_from_persister : Nil
    persister = MockEntityPersister.new @em, @em.class_metadata ForumUser
    @uow.set_entity_persister ForumUser, persister

    user = ForumUser.new
    user.username = "fred-original"
    pointerof(user.@id).value = 7
    @uow.register_managed user, {"id" => 7}, {"id" => 7, "username" => "fred-original"}

    # In-memory drift away from the DB row.
    user.username = "fred-stale-edit"

    fresh_data = Hash(String, DB::Any).new
    fresh_data["id"] = 7
    fresh_data["username"] = "fred-from-db"
    persister.mock_refresh_data = fresh_data

    @uow.refresh user

    user.username.should eq "fred-from-db"
    user.id.should eq 7
  end

  def test_refresh_raises_for_new_entity : Nil
    user = ForumUser.new
    user.username = "fred-new"

    # Never registered as managed.
    expect_raises(Exception, /not managed/) do
      @uow.refresh user
    end
  end

  def test_refresh_raises_for_removed_entity : Nil
    persister = MockEntityPersister.new @em, @em.class_metadata ForumUser
    @uow.set_entity_persister ForumUser, persister

    user = ForumUser.new
    user.username = "fred-removed"
    pointerof(user.@id).value = 9
    @uow.register_managed user, {"id" => 9}, {"id" => 9, "username" => "fred-removed"}
    @uow.schedule_for_delete user

    expect_raises(Exception, /not managed/) do
      @uow.refresh user
    end
  end

  def test_explicit_join_column_on_one_to_one_owning_side_overrides_default : Nil
    cm = @em.class_metadata CustomJoinOwner

    assoc = cm.association_mappings["linked"].not_nil!
    owning = assoc.as AORM::Mapping::OneToOneOwningSide
    owning.join_columns.size.should eq 1
    owning.join_columns.first.name.should eq "explicit_one_to_one_fk"
  end

  def test_explicit_join_column_on_many_to_one_owning_side_overrides_default : Nil
    cm = @em.class_metadata CustomJoinOwner

    assoc = cm.association_mappings["parent"].not_nil!
    owning = assoc.as AORM::Mapping::ManyToOneOwningSide
    owning.join_columns.size.should eq 1
    owning.join_columns.first.name.should eq "explicit_many_to_one_fk"
  end

  def test_one_to_many_inverse_side_metadata_uses_mapped_by : Nil
    cm = @em.class_metadata BlogUser

    assoc = cm.association_mappings["posts"].not_nil!
    assoc.should be_a AORM::Mapping::OneToManyInverseSide
    assoc.target_entity.should eq BlogPost
    assoc.as(AORM::Mapping::OneToManyInverseSide).mapped_by.should eq "user"
  end

  def test_many_to_one_owning_side_metadata_carries_join_column : Nil
    cm = @em.class_metadata BlogPost

    assoc = cm.association_mappings["user"].not_nil!
    assoc.should be_a AORM::Mapping::ManyToOneOwningSide
    assoc.target_entity.should eq BlogUser

    owning = assoc.as AORM::Mapping::ManyToOneOwningSide
    owning.source_to_target_key_columns.should eq({"user_id" => "id"})
  end

  def test_one_to_many_required_mapped_by : Nil
    # Direct construction without `mapped_by` should fail loudly — OneToMany
    # is always the inverse side, so the `mapped_by` pointer is mandatory.
    expect_raises(Exception, /mapped_by/) do
      AORM::Mapping::OneToManyInverseSide.new(
        AORM::Mapping::Driver::ColumnMapping.new(
          field_name: "x",
          source_entity: BlogUser,
          target_entity: BlogPost,
        )
      )
    end
  end

  def test_one_to_many_cascade_persist_writes_target_inserts : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata BlogUser
    @uow.set_entity_persister BlogUser, user_persister
    user_persister.mock_id_generator = :identity

    post_persister = MockEntityPersister.new @em, @em.class_metadata BlogPost
    @uow.set_entity_persister BlogPost, post_persister
    post_persister.mock_id_generator = :identity

    user = BlogUser.new
    user.username = "fred"
    p1 = BlogPost.new
    p1.title = "first"
    p2 = BlogPost.new
    p2.title = "second"
    user.posts << p1
    user.posts << p2

    @uow.persist user
    @uow.commit

    user.id.should be > 0
    user_persister.inserts.size.should eq 1
    # Both posts cascade-persisted off of `user.posts`.
    post_persister.inserts.size.should eq 2
  end

  def test_target_entity_inferred_from_to_one_property_type : Nil
    cm = @em.class_metadata InferredTargetOwner

    assoc = cm.association_mappings["primary"].not_nil!
    assoc.target_entity.should eq InferredTargetTag
  end

  def test_target_entity_inferred_from_collection_element_type : Nil
    cm = @em.class_metadata InferredTargetOwner

    assoc = cm.association_mappings["tags"].not_nil!
    assoc.target_entity.should eq InferredTargetTag
  end

  def test_index_by_annotation_reaches_mapping : Nil
    class_metadata = @em.class_metadata TagOwner

    assoc = class_metadata.association_mappings["tags"]?
    assoc.should_not be_nil
    assoc = assoc.not_nil!

    assoc.should be_a AORM::Mapping::ManyToManyOwningSide
    if assoc.is_a?(AORM::Mapping::ManyToManyOwningSide)
      assoc.index_by.should eq "name"
    end
  end

  def test_custom_join_table_annotation : Nil
    class_metadata = @em.class_metadata CustomJoinCategory

    assoc = class_metadata.association_mappings["products"]?
    assoc.should_not be_nil
    assoc = assoc.not_nil!

    assoc.should be_a AORM::Mapping::ManyToManyOwningSide
    if assoc.is_a?(AORM::Mapping::ManyToManyOwningSide)
      join_table = assoc.join_table
      join_table.should_not be_nil
      join_table.not_nil!.name.should eq "my_custom_join_table"
    end
  end

  def test_custom_join_column_annotations : Nil
    class_metadata = @em.class_metadata CustomColumnCategory

    assoc = class_metadata.association_mappings["products"]?
    assoc.should_not be_nil
    assoc = assoc.not_nil!

    assoc.should be_a AORM::Mapping::ManyToManyOwningSide
    if assoc.is_a?(AORM::Mapping::ManyToManyOwningSide)
      join_table = assoc.join_table
      join_table.should_not be_nil
      jt = join_table.not_nil!

      jt.name.should eq "category_product_map"

      # Check join columns (source entity to join table)
      jt.join_columns.size.should eq 1
      jt.join_columns[0].name.should eq "cat_id"
      jt.join_columns[0].referenced_column_name.should eq "id"

      # Check inverse join columns (join table to target entity)
      jt.inverse_join_columns.size.should eq 1
      jt.inverse_join_columns[0].name.should eq "prod_id"
      jt.inverse_join_columns[0].referenced_column_name.should eq "id"
    end
  end

  def test_bidirectional_association_sync_on_add : Nil
    user_persister = MockEntityPersister.new @em, @em.class_metadata CmsUser
    @uow.set_entity_persister CmsUser, user_persister
    user_persister.mock_id_generator = :identity

    group_persister = MockEntityPersister.new @em, @em.class_metadata CmsGroup
    @uow.set_entity_persister CmsGroup, group_persister
    group_persister.mock_id_generator = :identity

    user = CmsUser.new
    user.username = "test_user"

    group = CmsGroup.new
    group.name = "group1"

    # Owning-side helper updates both ends
    user.add_group group

    @uow.persist user
    @uow.commit

    group.users.includes?(user).should be_true
  end

  def test_schedule_for_delete_drops_an_insert_pending_entity : Nil
    persister = MockEntityPersister.new @em, @em.class_metadata CmsPhonenumber
    @uow.set_entity_persister CmsPhonenumber, persister

    phone = CmsPhonenumber.new
    phone.phonenumber = "555"

    @uow.persist phone
    @uow.is_scheduled_for_insert?(phone).should be_true

    @uow.schedule_for_delete phone

    # An entity scheduled for insertion that gets removed before flush should
    # disappear entirely, not be queued for deletion of a row that was never
    # inserted.
    @uow.is_scheduled_for_insert?(phone).should be_false
    @uow.is_scheduled_for_delete?(phone).should be_false
  end

  def test_schedule_for_update_raises_on_entity_without_identity : Nil
    user = ForumUser.new
    user.username = "Fred"
    # Never persisted, so the UoW has no identifier for it.

    expect_raises(Exception, /Entity has no identity/) do
      @uow.schedule_for_update user
    end
  end

  def test_schedule_for_update_raises_on_entity_scheduled_for_deletion : Nil
    persister = MockEntityPersister.new @em, @em.class_metadata CmsPhonenumber
    @uow.set_entity_persister CmsPhonenumber, persister

    phone = CmsPhonenumber.new
    phone.phonenumber = "555"

    @uow.persist phone
    @uow.commit
    @uow.schedule_for_delete phone

    expect_raises(Exception, /Entity scheduled for deletion/) do
      @uow.schedule_for_update phone
    end
  end

  def test_schedule_for_update_skips_entities_already_pending_insert : Nil
    persister = MockEntityPersister.new @em, @em.class_metadata VersionedAssignedIdentifierEntity
    @uow.set_entity_persister VersionedAssignedIdentifierEntity, persister

    entity = VersionedAssignedIdentifierEntity.new
    entity.id = 1

    @uow.persist entity
    @uow.is_scheduled_for_insert?(entity).should be_true

    @uow.schedule_for_update entity

    # Insert-pending entities don't double-up as updates — the insert will
    # already write the current state when it executes.
    @uow.is_scheduled_for_update?(entity).should be_false
    @uow.is_scheduled_for_insert?(entity).should be_true
  end

  def test_id_hash_by_identifier_joins_single_key : Nil
    AORM::UnitOfWork.id_hash_by_identifier({"id" => 42}).should eq "42"
  end

  def test_id_hash_by_identifier_joins_composite_keys_with_space : Nil
    # Composite identifier values are flattened into a single space-separated
    # string for use as the identity-map key.
    AORM::UnitOfWork.id_hash_by_identifier({"a" => 1, "b" => 2}).should eq "1 2"
  end

  def test_id_hash_by_identifier_handles_empty_string_single_key : Nil
    AORM::UnitOfWork.id_hash_by_identifier({"id" => ""}).should eq ""
  end

  def test_id_hash_by_identifier_handles_empty_string_composite_keys : Nil
    # Two empty values still produce the separator between them.
    AORM::UnitOfWork.id_hash_by_identifier({"id1" => "", "id2" => ""}).should eq " "
  end

  def test_id_hash_by_identifier_renders_boolean_true_as_1 : Nil
    AORM::UnitOfWork.id_hash_by_identifier({"id" => true}).should eq "1"
  end

  def test_id_hash_by_identifier_renders_boolean_false_as_empty : Nil
    AORM::UnitOfWork.id_hash_by_identifier({"id" => false}).should eq ""
  end

  # ===== Identity map =====

  def test_add_to_identity_map_returns_true_when_inserting_a_new_entry : Nil
    phone = managed_phone "555-0001"

    @uow.is_in_identity_map(phone).should be_true
  end

  def test_add_to_identity_map_is_idempotent_for_the_same_instance : Nil
    phone = managed_phone "555-0002"

    @uow.add_to_identity_map(phone).should be_false
  end

  def test_add_to_identity_map_raises_on_collision_with_a_different_instance : Nil
    managed_phone "555-0003"

    other = CmsPhonenumber.new
    other.phonenumber = "555-0003"
    @uow.@entity_identifiers[other] = {"phonenumber" => AORM::Mapping::ColumnValue(String).new("phonenumber", "555-0003").as(AORM::Mapping::Value)}

    expect_raises(Exception, /identity collision/) do
      @uow.add_to_identity_map other
    end
  end

  def test_remove_from_identity_map_returns_true_when_present : Nil
    phone = managed_phone "555-0004"

    @uow.remove_from_identity_map(phone).should be_true
    @uow.is_in_identity_map(phone).should be_false
  end

  def test_remove_from_identity_map_returns_false_when_not_present : Nil
    phone = managed_phone "555-0005"
    @uow.remove_from_identity_map phone

    @uow.remove_from_identity_map(phone).should be_false
  end

  def test_get_by_id_hash_returns_entity_for_known_hash : Nil
    phone = managed_phone "555-0006"

    @uow.get_by_id_hash("555-0006", CmsPhonenumber).should be phone
  end

  def test_get_by_id_hash_returns_nil_for_unknown_hash : Nil
    managed_phone "555-0007"

    @uow.get_by_id_hash("nope", CmsPhonenumber).should be_nil
  end

  def test_try_get_by_id_yields_the_entity_when_present : Nil
    phone = managed_phone "555-0008"
    yielded = nil

    @uow.try_get_by_id({"phonenumber" => "555-0008"}, CmsPhonenumber) do |entity|
      yielded = entity
    end

    yielded.should be phone
  end

  def test_try_get_by_id_does_not_yield_when_absent : Nil
    managed_phone "555-0009"
    yielded = false

    @uow.try_get_by_id({"phonenumber" => "missing"}, CmsPhonenumber) { yielded = true }

    yielded.should be_false
  end

  # ===== Entity state =====

  def test_entity_state_is_managed_after_register_managed : Nil
    phone = managed_phone "555-1000"

    @uow.entity_state(phone).should eq AORM::UnitOfWork::EntityState::Managed
  end

  def test_entity_state_returns_assume_when_state_is_unknown : Nil
    user = ForumUser.new

    @uow.entity_state(user, AORM::UnitOfWork::EntityState::Detached).should eq AORM::UnitOfWork::EntityState::Detached
  end

  def test_entity_identifier_returns_the_registered_value : Nil
    phone = managed_phone "555-1001"

    @uow.entity_identifier(phone)["phonenumber"].value.should eq "555-1001"
  end

  def test_entity_identifier_raises_for_an_unknown_entity : Nil
    user = ForumUser.new

    expect_raises(Exception, /Unable to find/) do
      @uow.entity_identifier user
    end
  end

  # Helper: create a CmsPhonenumber, register it as managed with the given id,
  # and return it. Bypasses persistence so identity-map / state tests don't
  # need persister setup.
  private def managed_phone(number : String) : CmsPhonenumber
    phone = CmsPhonenumber.new
    phone.phonenumber = number
    @uow.register_managed phone, {"phonenumber" => number}, {"phonenumber" => number}
    phone
  end

  # ToOne owning-side hydration: when the FK target is already in the identity
  # map, `create_entity` resolves the property inline — no deferred query.
  def test_create_entity_resolves_to_one_owning_side_from_identity_map : Nil
    avatar = ForumAvatar.new
    pointerof(avatar.@id).value = 42
    @uow.register_managed avatar, {"id" => 42}, {"id" => 42}

    data = Hash(String, AORM::Mapping::Value).new
    data["id"] = AORM::Mapping::SingleValue(Int32).new(7)
    data["username"] = AORM::Mapping::SingleValue(String).new("fred")
    # The hydrator's meta-mapping branch deposits FK columns under the
    # column name (not the assoc field name) in the row data hash.
    data["avatar_id"] = AORM::Mapping::SingleValue(Int32).new(42)

    user = @uow.create_entity(ForumUser, data).as ForumUser

    user.avatar.should be avatar
    @uow.resolve_pending_to_one_associations
    user.avatar.should be avatar
  end

  # ToOne owning-side hydration: when the FK target isn't in the identity map,
  # the resolution is queued and runs only when the hydrator's `cleanup` fires
  # (driven here by `resolve_pending_to_one_associations`).
  # The persister's `load(id_hash)` is what actually fetches the target.
  def test_create_entity_defers_to_one_owning_side_when_target_not_in_identity_map : Nil
    canned_avatar = ForumAvatar.new
    pointerof(canned_avatar.@id).value = 99

    avatar_persister = MockEntityPersister.new @em, @em.class_metadata ForumAvatar
    avatar_persister.mock_load_result = canned_avatar
    @uow.set_entity_persister ForumAvatar, avatar_persister

    data = Hash(String, AORM::Mapping::Value).new
    data["id"] = AORM::Mapping::SingleValue(Int32).new(7)
    data["username"] = AORM::Mapping::SingleValue(String).new("fred")
    data["avatar_id"] = AORM::Mapping::SingleValue(Int32).new(99)

    user = @uow.create_entity(ForumUser, data).as ForumUser

    # Inline access during hydration: the FK target hasn't been fetched yet.
    avatar_persister.load_calls.should be_empty

    # Hydrator's `cleanup` triggers this in real flows; call it directly here.
    @uow.resolve_pending_to_one_associations

    avatar_persister.load_calls.size.should eq 1
    user.avatar.should be canned_avatar
  end
end

# Helper persister that throws an exception during execute_inserts
class FailingEntityPersister < MockEntityPersister
  def initialize(@em : AORM::EntityManagerInterface, @class_metadata : AORM::Mapping::ClassInterface, @error_message : String)
    super(@em, @class_metadata)
  end

  def execute_inserts : Nil
    raise @error_message
  end
end
