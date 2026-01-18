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

struct UnitOfWorkTest < ASPEC::TestCase
  @connection : DB::Connection
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

  @[Pending]
  def test_removed_entity_is_removed_from_many_to_many_collection : Nil
    # Requires: ManyToMany association support
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
