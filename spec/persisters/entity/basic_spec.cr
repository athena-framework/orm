require "../../spec_helper"

# Composite-PK fixture for ORDER BY coverage.
@[AORMA::Entity]
@[AORMA::Table(name: "composite_pk_items")]
class CompositePkItem < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property tenant_id : String? = nil

  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property item_id : String? = nil

  @[AORMA::Column]
  property! label : String
end

# Composite-PK + auto-gen: only viable through the RETURNING path, since
# `LASTVAL()` can only return a single column.
@[AORMA::Entity]
@[AORMA::Table(name: "composite_auto_items")]
class CompositeAutoItem < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! tenant_id : Int64

  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! item_id : Int64

  @[AORMA::Column]
  property! label : String
end

# OneToMany inverse-side / ManyToOne owning-side pair, used to drive the inverse-side branch in `select_condition_statement_column_sql`.
@[AORMA::Entity]
@[AORMA::Table(name: "tag_owners")]
class TagOwnerWithTags < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::OneToMany(mapped_by: "owner")]
  property tags : AORM::Collection(OwnedTag) = AORM::ArrayCollection(OwnedTag).new
end

@[AORMA::Entity]
@[AORMA::Table(name: "owned_tags")]
class OwnedTag < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::ManyToOne]
  property owner : TagOwnerWithTags? = nil
end

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

  # SELECT shape: bare query against the persister's class without criteria.
  # Output is a single-table SELECT with the entity's quoted table name and a generated alias.
  def test_select_sql_emits_select_from_with_table_alias : Nil
    persister = build_persister

    sql = persister.select_sql(Hash(String, DB::Any).new)

    sql.should match(/^SELECT .+ FROM forum_users t\d+/)
  end

  # Criteria appended to SELECT route through select_condition_sql to produce a WHERE clause with placeholders.
  def test_select_sql_appends_where_clause_when_criteria_present : Nil
    persister = build_persister

    sql = persister.select_sql({"username" => "fred".as(DB::Any)})

    sql.should match(/\bWHERE\b/)
    sql.should match(/username = \?/)
  end

  # ORDER BY arg flows into order_by_sql, which uses the table alias the persister already chose.
  def test_select_sql_appends_order_by_when_present : Nil
    persister = build_persister

    sql = persister.select_sql(Hash(String, DB::Any).new, order_by: {"username" => "ASC"})

    sql.should match(/ORDER BY t\d+\.username ASC/)
  end

  # ORDER BY must come AFTER the WHERE clause when both are present, so the splice point in the generated SQL is correct.
  def test_select_sql_orders_after_where_clause : Nil
    persister = build_persister

    sql = persister.select_sql({"username" => "fred".as(DB::Any)}, order_by: {"username" => "DESC"})

    sql.index(" WHERE ").not_nil!.should be < sql.index(" ORDER BY ").not_nil!
  end

  # No order_by argument means no ORDER BY clause — empty string spliced in cleanly.
  def test_select_sql_omits_order_by_when_not_provided : Nil
    persister = build_persister

    sql = persister.select_sql(Hash(String, DB::Any).new)

    sql.should_not match(/\bORDER BY\b/)
  end

  # The persister selects every mapped field as `<alias>.<col> AS <result_alias>`, plus one entry per ToOne owning-side join column for hydrator meta-results.
  def test_select_columns_sql_lists_field_and_to_one_fk_columns : Nil
    persister = build_persister

    sql = persister.select_columns_sql

    sql.should match(/t\d+\.username AS \w+/)
    sql.should match(/t\d+\.avatar_id AS \w+/)
  end

  # `select_column_association_sql` is the FK-emitting helper for ToOne owning sides.
  # It registers each join column as a meta-result on the RSM and returns `<alias>.<col> AS <result_alias>`.
  def test_select_column_association_sql_emits_fk_for_to_one_owning : Nil
    persister = build_persister
    cm = persister.@em.class_metadata ForumUser
    assoc = cm.association_mappings["avatar"].not_nil!

    sql = persister.select_column_association_sql("avatar", assoc, cm)

    sql.should match(/t\d+\.avatar_id AS \w+/)
  end

  # ToMany associations have no FK column on the owner's table, so the helper returns an empty string.
  def test_select_column_association_sql_returns_empty_for_to_many : Nil
    em = MockEntityManager.new(MockConnection.new)
    persister = AORM::Persisters::Entity::Basic.new em, em.class_metadata(CmsUser)
    cm = em.class_metadata CmsUser
    assoc = cm.association_mappings["groups"].not_nil!

    persister.select_column_association_sql("groups", assoc, cm).should eq ""
  end

  # ManyToMany loads emit an INNER JOIN against the join table on the owner's PK to the join table's inverse-side FK column.
  def test_select_many_to_many_join_sql_emits_inner_join_clause : Nil
    em = MockEntityManager.new(MockConnection.new)
    persister = AORM::Persisters::Entity::Basic.new em, em.class_metadata(CmsUser)
    cm = em.class_metadata CmsUser
    assoc = cm.association_mappings["groups"].not_nil!.as AORM::Mapping::ManyToMany

    sql = persister.select_many_to_many_join_sql assoc

    sql.should start_with " INNER JOIN "
    sql.should match(/\bON\b/)
    sql.should match(/t\d+\.\w+ = \w+\.\w+/)
  end

  # `sql_table_alias` is keyed by entity_class + assoc_name; repeated calls for the same key return the cached alias rather than minting a fresh one.
  def test_sql_table_alias_caches_per_entity : Nil
    persister = build_persister

    first = persister.sql_table_alias ForumUser
    second = persister.sql_table_alias ForumUser

    first.should match(/^t\d+$/)
    first.should eq second
  end

  # Distinct entity classes get distinct aliases so multi-table SELECTs don't collide.
  def test_sql_table_alias_yields_distinct_aliases_for_different_entities : Nil
    persister = build_persister

    forum_alias = persister.sql_table_alias ForumUser
    avatar_alias = persister.sql_table_alias ForumAvatar

    forum_alias.should_not eq avatar_alias
  end

  # `sql_column_alias` rendering is delegated to the quote strategy; it must always return a non-empty identifier safe to splice into SQL.
  def test_sql_column_alias_returns_non_empty_identifier : Nil
    persister = build_persister

    alias_name = persister.sql_column_alias("username")

    alias_name.should_not be_empty
    alias_name.should match(/^\w+$/)
  end

  # Filtering by a ManyToMany association field is not supported on the persister side.
  def test_select_condition_statement_sql_raises_for_many_to_many_field : Nil
    em = MockEntityManager.new(MockConnection.new)
    persister = AORM::Persisters::Entity::Basic.new em, em.class_metadata(CmsUser)

    user = CmsUser.new
    user.username = "fred"

    expect_raises(Exception, /ManyToMany/) do
      persister.select_condition_statement_sql("groups", user)
    end
  end

  # Filtering by an inverse-side OneToMany must redirect to the owning side; the persister refuses to guess.
  def test_select_condition_statement_sql_raises_for_inverse_side_field : Nil
    em = MockEntityManager.new(MockConnection.new)
    persister = AORM::Persisters::Entity::Basic.new em, em.class_metadata(TagOwnerWithTags)

    tag = OwnedTag.new

    expect_raises(Exception, /inverse side/) do
      persister.select_condition_statement_sql("tags", tag)
    end
  end

  # Composite-PK ORDER BY: each PK component gets its own clause separated by commas, alphabetized by the input hash's order.
  def test_order_by_sql_renders_composite_identifier_fields : Nil
    em = MockEntityManager.new(MockConnection.new)
    persister = AORM::Persisters::Entity::Basic.new em, em.class_metadata(CompositePkItem)

    sql = persister.order_by_sql({"tenant_id" => "ASC", "item_id" => "DESC"}, "t0")

    sql.should eq " ORDER BY t0.tenant_id ASC, t0.item_id DESC"
  end

  def test_execute_inserts_appends_returning_clause_on_supporting_platform : Nil
    connection = MockConnection.new
    em = MockEntityManager.new(connection)
    persister = AORM::Persisters::Entity::Basic.new em, em.class_metadata(CompositeAutoItem)

    item = CompositeAutoItem.new
    item.label = "widget"

    em.unit_of_work.persist item
    persister.add_insert item
    persister.execute_inserts

    insert_sql = connection.built_statements.last
    insert_sql.should match(/INSERT INTO\s+composite_auto_items\b/)
    insert_sql.should match(/\bRETURNING\s+tenant_id,\s*item_id\b/)
    item.tenant_id.should eq 1_i64
    item.item_id.should eq 1_i64
  end

  def test_execute_inserts_emits_plain_insert_on_non_returning_platform : Nil
    connection = MockMariaConnection.new
    em = MockEntityManager.new(connection)
    persister = AORM::Persisters::Entity::Basic.new em, em.class_metadata(ForumUser)

    avatar = ForumAvatar.new
    em.unit_of_work.register_managed avatar, {"id" => 99}, {"id" => 99}

    user = ForumUser.new
    user.username = "fred"
    user.avatar = avatar

    connection.push_ids Int32, 42

    em.unit_of_work.persist user
    persister.add_insert user
    persister.execute_inserts

    insert_sql = connection.built_statements.last
    insert_sql.should match(/INSERT INTO\s+forum_users\b/)
    insert_sql.should_not match(/\bRETURNING\b/)
    user.id.should eq 42
  end

  private def build_persister : AORM::Persisters::Entity::Basic
    em = MockEntityManager.new(MockConnection.new)
    AORM::Persisters::Entity::Basic.new em, em.class_metadata(ForumUser)
  end
end
