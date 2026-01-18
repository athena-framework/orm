require "./spec_helper"

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
end
