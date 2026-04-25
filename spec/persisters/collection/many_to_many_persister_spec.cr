require "../../spec_helper"

# Friend subclass that exposes the protected SQL/param helpers so we can
# assert their output without driving a real DB exec.
private class TestableManyToManyPersister < AORM::Persisters::Collection::ManyToManyPersister
  def public_get_delete_sql(mapping)
    self.get_delete_sql mapping
  end

  def public_get_delete_row_sql(mapping)
    self.get_delete_row_sql mapping
  end

  def public_get_insert_row_sql(mapping)
    self.get_insert_row_sql mapping
  end

  def public_get_delete_sql_params(collection, mapping)
    self.get_delete_sql_params collection, mapping
  end

  def public_get_delete_row_sql_params(collection, element, mapping)
    self.get_delete_row_sql_params collection, element, mapping
  end

  def public_get_insert_row_sql_params(collection, element, mapping)
    self.get_insert_row_sql_params collection, element, mapping
  end
end

struct ManyToManyPersisterTest < ASPEC::TestCase
  # ===== SQL generation =====

  def test_get_delete_sql_targets_join_table_with_owner_key_in_where : Nil
    persister = build_persister
    mapping = cms_user_groups_mapping

    sql = persister.public_get_delete_sql mapping

    sql.should eq "DELETE FROM cms_user_cms_group WHERE cms_user_id = ?"
  end

  def test_get_delete_row_sql_includes_owner_and_element_keys : Nil
    persister = build_persister
    mapping = cms_user_groups_mapping

    sql = persister.public_get_delete_row_sql mapping

    sql.should eq "DELETE FROM cms_user_cms_group WHERE cms_user_id = ? AND cms_group_id = ?"
  end

  def test_get_insert_row_sql_lists_join_columns_in_order : Nil
    persister = build_persister
    mapping = cms_user_groups_mapping

    sql = persister.public_get_insert_row_sql mapping

    sql.should eq "INSERT INTO cms_user_cms_group (cms_user_id, cms_group_id) VALUES (?, ?)"
  end

  # ===== Parameter binding =====

  def test_get_delete_sql_params_returns_owner_identifier : Nil
    persister, mapping = build_persister_with_mapping
    user = managed_user 100

    collection = AORM::PersistentCollection(CmsGroup).new
    collection.set_owner user, mapping

    params = persister.public_get_delete_sql_params collection, mapping

    params.should eq [100]
  end

  def test_get_delete_row_sql_params_pairs_owner_then_element_ids : Nil
    persister, mapping = build_persister_with_mapping
    user = managed_user 7
    group = managed_group 99

    collection = AORM::PersistentCollection(CmsGroup).new
    collection.set_owner user, mapping

    params = persister.public_get_delete_row_sql_params collection, group, mapping

    # Source key columns precede target key columns — must match the order in
    # the generated SQL so positional placeholders bind correctly.
    params.should eq [7, 99]
  end

  def test_get_insert_row_sql_params_uses_same_ordering_as_delete : Nil
    persister, mapping = build_persister_with_mapping
    user = managed_user 1
    group = managed_group 2

    collection = AORM::PersistentCollection(CmsGroup).new
    collection.set_owner user, mapping

    params = persister.public_get_insert_row_sql_params collection, group, mapping

    params.should eq [1, 2]
  end

  # ===== Setup helpers =====

  private def build_persister : TestableManyToManyPersister
    TestableManyToManyPersister.new @em
  end

  private def build_persister_with_mapping : {TestableManyToManyPersister, AORM::Mapping::ManyToManyOwningSide}
    {build_persister, cms_user_groups_mapping}
  end

  private def cms_user_groups_mapping : AORM::Mapping::ManyToManyOwningSide
    @em.class_metadata(CmsUser).association_mappings["groups"].as(AORM::Mapping::ManyToManyOwningSide)
  end

  private def managed_user(id : Int32) : CmsUser
    user = CmsUser.new
    user.username = "u#{id}"
    user.id = id
    @uow.register_managed user, {"id" => id}, {"id" => id}
    user
  end

  private def managed_group(id : Int32) : CmsGroup
    group = CmsGroup.new
    group.name = "g#{id}"
    group.id = id
    @uow.register_managed group, {"id" => id}, {"id" => id}
    group
  end

  @em : MockEntityManager
  @uow : AORM::UnitOfWork

  def initialize
    @em = MockEntityManager.new(MockConnection.new)
    @uow = @em.unit_of_work
  end
end
