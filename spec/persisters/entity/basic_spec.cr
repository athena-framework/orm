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

  private def build_persister : AORM::Persisters::Entity::Basic
    em = MockEntityManager.new(MockConnection.new)
    AORM::Persisters::Entity::Basic.new em, em.class_metadata(ForumUser)
  end
end
