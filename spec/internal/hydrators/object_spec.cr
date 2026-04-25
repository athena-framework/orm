require "../../spec_helper"

# Two-column identifier so we can verify gather_row_data's composite id concat.
@[AORMA::Entity]
class HydratorCompositeIdEntity < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property id1 : String? = nil

  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property id2 : String? = nil
end

# Subclass that exposes `@id_template` for regression assertions.
private class IdTemplateInspectingHydrator < AORM::Internal::Hydrators::Object
  getter id_template
end

struct ObjectHydratorTest < ASPEC::TestCase
  def test_id_template_not_mutated_across_rows : Nil
    em = MockEntityManager.new(MockConnection.new)
    rsm = AORM::Query::ResultSetMapping.new
    rsm.add_root_entity CmsPhonenumber, "p"
    rsm.add_field_result "p", "p__phonenumber", "phonenumber"

    rs = FakeResultSet.new([
      {"p__phonenumber" => "555-0001".as(DB::Any)},
    ])

    hydrator = IdTemplateInspectingHydrator.new(em)
    hydrator.hydrate_all(rs, rsm)

    # Regression: gather_row_data mutates the per-row id hash via `+=`.
    # Before the fix, `id` aliased `@id_template`, so the template grew
    # across rows and broke root-entity dedup. The fix dups per row, leaving
    # the template's seeded empty strings intact.
    hydrator.id_template["p"].should eq ""
  end

  # Multiple distinct rows for the same root alias produce one entity per row in source order.
  def test_simple_entity_query_returns_one_entity_per_distinct_row : Nil
    em = MockEntityManager.new(MockConnection.new)
    rsm = AORM::Query::ResultSetMapping.new
    rsm.add_root_entity CmsPhonenumber, "p"
    rsm.add_field_result "p", "p__phonenumber", "phonenumber"

    rs = FakeResultSet.new([
      {"p__phonenumber" => "555-0001".as(DB::Any)},
      {"p__phonenumber" => "555-0002".as(DB::Any)},
    ])

    result = AORM::Internal::Hydrators::Object.new(em).hydrate_all(rs, rsm)

    result.size.should eq 2
    result.map(&.as(CmsPhonenumber).phonenumber).should eq ["555-0001", "555-0002"]
  end

  # Multiple rows that all carry the same identifier should resolve to a single
  # entity instance — this is what makes fetch-joins safe (the same root row
  # repeats once per joined child) and what makes the id_template dedup matter.
  def test_repeated_identifier_in_consecutive_rows_resolves_to_one_entity : Nil
    em = MockEntityManager.new(MockConnection.new)
    rsm = AORM::Query::ResultSetMapping.new
    rsm.add_root_entity CmsPhonenumber, "p"
    rsm.add_field_result "p", "p__phonenumber", "phonenumber"

    rs = FakeResultSet.new([
      {"p__phonenumber" => "555-1000".as(DB::Any)},
      {"p__phonenumber" => "555-1000".as(DB::Any)},
    ])

    result = AORM::Internal::Hydrators::Object.new(em).hydrate_all(rs, rsm)

    # Identity-map dedup: same id_hash → same instance returned by
    # `uow.create_entity`, so the result has one entry.
    result.size.should eq 1
    result[0].as(CmsPhonenumber).phonenumber.should eq "555-1000"
  end

  # Composite identifier: gather_row_data concatenates each id column into a
  # single per-alias key, separated by `|`. Rows that differ in any one id
  # column hash differently and become distinct entities.
  def test_composite_identifier_uniqueness_across_both_columns : Nil
    em = MockEntityManager.new(MockConnection.new)
    rsm = AORM::Query::ResultSetMapping.new
    rsm.add_root_entity HydratorCompositeIdEntity, "e"
    rsm.add_field_result "e", "e__id1", "id1"
    rsm.add_field_result "e", "e__id2", "id2"

    rs = FakeResultSet.new([
      {"e__id1" => "a".as(DB::Any), "e__id2" => "x".as(DB::Any)},
      {"e__id1" => "a".as(DB::Any), "e__id2" => "y".as(DB::Any)}, # same id1, different id2 → distinct
      {"e__id1" => "a".as(DB::Any), "e__id2" => "x".as(DB::Any)}, # exact repeat → dedup
    ])

    result = AORM::Internal::Hydrators::Object.new(em).hydrate_all(rs, rsm)

    result.size.should eq 2
    pairs = result.map { |e| e.as(HydratorCompositeIdEntity) }
      .map { |e| {e.id1, e.id2} }
    pairs.should eq [{"a", "x"}, {"a", "y"}]
  end
end
