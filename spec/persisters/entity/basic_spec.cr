require "../../spec_helper"

struct BasicPersisterTest < ASPEC::TestCase
  def test_select_condition_eq_emits_placeholder : Nil
    persister = build_persister

    persister.select_condition_statement_sql("id", 1).should match(/id = \?/)
  end

  def test_select_condition_eq_nil_emits_is_null : Nil
    persister = build_persister

    persister.select_condition_statement_sql("id", nil).should match(/id IS NULL/)
  end

  def test_select_condition_neq_nil_emits_is_not_null : Nil
    persister = build_persister

    persister.select_condition_statement_sql("id", nil, comparison: "<>").should match(/id IS NOT NULL/)
  end

  def test_select_condition_array_emits_in_clause : Nil
    persister = build_persister

    sql = persister.select_condition_statement_sql("id", [1, 2, 3])

    sql.should match(/id IN \(\?, \?, \?\)/)
  end

  def test_select_condition_empty_array_emits_unsatisfiable : Nil
    persister = build_persister

    persister.select_condition_statement_sql("id", [] of Int32).should match(/1=0/)
  end

  def test_select_condition_array_with_nil_adds_is_null_branch : Nil
    persister = build_persister

    sql = persister.select_condition_statement_sql("id", [1, nil, 2])

    # Two non-nil values plus a NULL branch. Column is qualified by table alias.
    sql.should match(/\(t\d+\.id IN \(\?, \?\) OR t\d+\.id IS NULL\)/)
  end

  def test_select_condition_array_of_only_nils_emits_is_null : Nil
    persister = build_persister

    persister.select_condition_statement_sql("id", [nil, nil] of Int32?).should match(/id IS NULL/)
  end

  def test_select_condition_to_one_owning_side_emits_join_column : Nil
    persister = build_persister

    avatar = ForumAvatar.new

    sql = persister.select_condition_statement_sql("avatar", avatar)

    # ForumUser maps `avatar` via `@[AORMA::JoinColumn(name: "avatar_id", ...)]`
    sql.should match(/avatar_id = \?/)
  end

  def test_expand_parameters_skips_nil : Nil
    persister = build_persister

    persister.expand_parameters({"id" => nil.as(DB::Any)}).should be_empty
  end

  def test_expand_parameters_flattens_array_and_drops_nils : Nil
    persister = build_persister

    params = persister.expand_parameters({"id" => [1, nil, 3].as(Array(Int32?))})

    params.size.should eq 2
  end

  def test_expand_parameters_resolves_an_entity_to_its_identifier_value : Nil
    persister = build_persister

    avatar = ForumAvatar.new
    em = persister.@em
    em.unit_of_work.register_managed avatar, {"id" => 99}, {"id" => 99}

    params = persister.expand_parameters({"avatar" => avatar})

    params.size.should eq 1
    params.first.should eq 99
  end

  def test_prepare_insert_data_writes_to_one_owning_side_fk_column : Nil
    em = MockEntityManager.new(MockConnection.new)
    persister = MockEntityPersister.new em, em.class_metadata(ForumUser)

    avatar = ForumAvatar.new
    em.unit_of_work.register_managed avatar, {"id" => 99}, {"id" => 99}

    user = ForumUser.new
    user.username = "fred"
    user.avatar = avatar

    em.unit_of_work.persist user
    em.unit_of_work.compute_changesets

    data = persister.insert_data_for user
    user_row = data["forum_users"]

    user_row["username"].value.should eq "fred"
    # avatar_id mirrors the avatar's identifier so the FK is written on insert.
    user_row["avatar_id"].value.should eq 99
  end

  def test_prepare_insert_data_writes_null_fk_when_target_still_queued : Nil
    em = MockEntityManager.new(MockConnection.new)
    persister = MockEntityPersister.new em, em.class_metadata(ForumUser)

    avatar = ForumAvatar.new
    user = ForumUser.new
    user.username = "fred"
    user.avatar = avatar

    # Both entities are scheduled for insert and the target has no identifier
    # yet: the FK column gets NULL on this INSERT and an extra UPDATE gets
    # scheduled to patch it once the target has an id.
    em.unit_of_work.persist user
    em.unit_of_work.compute_changesets

    data = persister.insert_data_for user
    user_row = data["forum_users"]

    user_row["avatar_id"].value.should be_nil
    em.unit_of_work.extra_update_for(user).has_key?("avatar").should be_true
  end

  def test_insert_sql_lists_columns_and_placeholders : Nil
    persister = build_persister

    sql = persister.insert_sql

    sql.should start_with "INSERT INTO"
    sql.should match /\bforum_users\b/
    # ForumUser has username (column) + avatar (FK via @[AORMA::JoinColumn(name: "avatar_id")])
    sql.should match /\busername\b/
    sql.should match /\bavatar_id\b/
    # ID column is identity-strategy → omitted from the explicit column list.
    sql.should_not match /\(.*\bid\b.*\)/
  end

  def test_insert_column_list_emits_join_columns_for_to_one_owning_side : Nil
    persister = build_persister

    columns = persister.insert_column_list

    # ForumUser → avatar is a ToOne owning side mapped to "avatar_id".
    columns.should contain "avatar_id"
    columns.should contain "username"
  end

  def test_select_condition_sql_joins_multiple_predicates_with_and : Nil
    persister = build_persister

    sql = persister.select_condition_sql({"id" => 1, "username" => "fred"})

    sql.scan(/\bAND\b/).size.should eq 1
  end

  def test_select_condition_sql_emits_is_null_for_nil_values : Nil
    persister = build_persister

    sql = persister.select_condition_sql({"username" => nil})

    sql.should match /username\s+IS NULL/
  end

  def test_select_condition_statement_sql_emits_each_comparison_operator : Nil
    persister = build_persister

    {
      "="  => /id = \?/,
      "<>" => /id != \?/,
      ">"  => /id > \?/,
      ">=" => /id >= \?/,
      "<"  => /id < \?/,
      "<=" => /id <= \?/,
    }.each do |op, expected|
      sql = persister.select_condition_statement_sql("id", 1, comparison: op)
      sql.should match expected
    end
  end

  def test_select_condition_statement_sql_with_nin_keeps_in_then_or_null : Nil
    persister = build_persister

    sql = persister.select_condition_statement_sql("id", [1, nil, 2], comparison: "NIN")

    # NIN mirrors IN's NULL split, just with NOT IN.
    sql.should match(/\(t\d+\.id NOT IN \(\?, \?\) OR t\d+\.id IS NULL\)/)
  end

  def test_select_condition_statement_column_sql_raises_for_unknown_field : Nil
    persister = build_persister

    expect_raises(Exception, /unrecognized field/) do
      persister.select_condition_statement_sql("nonexistent_field", 1)
    end
  end

  def test_expand_parameters_passes_through_scalar_types : Nil
    persister = build_persister

    # Each scalar value becomes one positional parameter — no transformation,
    # no flattening for non-Indexable values.
    params = persister.expand_parameters({
      "id"       => 42,
      "username" => "fred",
    })

    params.size.should eq 2
    params.includes?(42).should be_true
    params.includes?("fred").should be_true
  end

  def test_expand_parameters_returns_empty_for_all_nil_criteria : Nil
    persister = build_persister

    persister.expand_parameters({"id" => nil, "username" => nil}).should be_empty
  end

  def test_count_sql_with_no_criteria_omits_where_clause : Nil
    persister = build_persister

    sql = persister.count_sql(Hash(String, DB::Any).new)

    sql.should match(/^SELECT COUNT\(\*\) FROM forum_users\b/)
    sql.should_not match(/\bWHERE\b/)
  end

  def test_count_sql_with_criteria_appends_where_clause : Nil
    persister = build_persister

    sql = persister.count_sql({"username" => "fred"})

    sql.should match(/^SELECT COUNT\(\*\) FROM forum_users\b/)
    sql.should match(/\bWHERE\b/)
    sql.should match(/username = \?/)
  end

  def test_order_by_sql_returns_empty_for_empty_input : Nil
    persister = build_persister

    persister.order_by_sql(Hash(String, String).new, "t0").should eq ""
  end

  def test_order_by_sql_emits_explicit_orientation : Nil
    persister = build_persister

    persister.order_by_sql({"username" => "DESC"}, "t0").should eq " ORDER BY t0.username DESC"
    persister.order_by_sql({"username" => "ASC"}, "t0").should eq " ORDER BY t0.username ASC"
  end

  def test_order_by_sql_normalizes_lowercase_orientation : Nil
    persister = build_persister

    persister.order_by_sql({"username" => "desc"}, "t0").should eq " ORDER BY t0.username DESC"
  end

  def test_order_by_sql_joins_multiple_entries_with_comma : Nil
    persister = build_persister

    sql = persister.order_by_sql({"username" => "ASC", "id" => "DESC"}, "t0")

    sql.should eq " ORDER BY t0.username ASC, t0.id DESC"
  end

  def test_order_by_sql_expands_to_one_to_owning_side_join_columns : Nil
    persister = build_persister

    # ForumUser.avatar is the ToOne owning side; its join column is `avatar_id`.
    sql = persister.order_by_sql({"avatar" => "ASC"}, "t0")

    sql.should eq " ORDER BY t0.avatar_id ASC"
  end

  def test_order_by_sql_raises_on_invalid_orientation : Nil
    persister = build_persister

    expect_raises(Exception, /Invalid ORDER BY orientation/) do
      persister.order_by_sql({"username" => "SIDEWAYS"}, "t0")
    end
  end

  def test_order_by_sql_raises_on_unrecognized_field : Nil
    persister = build_persister

    expect_raises(Exception, /Unrecognized field/) do
      persister.order_by_sql({"nonexistent" => "ASC"}, "t0")
    end
  end

  private def build_persister : AORM::Persisters::Entity::Basic
    em = MockEntityManager.new(MockConnection.new)
    AORM::Persisters::Entity::Basic.new em, em.class_metadata(ForumUser)
  end
end
