require "./spec_helper"
require "uuid"

# Inline test entities (like Doctrine's test-only entities)
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
      "boolean true"  => {bool_true, "true"},
      "boolean false" => {bool_false, "false"},
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

    # Now remove group1 (using remove, which triggers remove_from_collections)
    @uow.remove group1

    # The group should be removed from the user's collection
    user.groups.includes?(group1).should be_false
    user.groups.size.should eq 1
    user.groups.includes?(group2).should be_true
  end

  @[Pending]
  def test_removed_entity_is_removed_from_one_to_many_collection : Nil
    # Requires: OneToMany association support
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

    # Add group to user's collection (owning side)
    user.groups << group

    @uow.persist user
    @uow.commit

    # After flush, the back-reference should be synced
    # The group's users collection should contain the user
    group.users.includes?(user).should be_true
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
