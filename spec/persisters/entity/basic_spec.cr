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

  private def build_persister : AORM::Persisters::Entity::Basic
    em = MockEntityManager.new(MockConnection.new)
    AORM::Persisters::Entity::Basic.new em, em.class_metadata(ForumUser)
  end
end
