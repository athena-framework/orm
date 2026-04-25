require "../../spec_helper"

# Mock result set that yields a fixed list of `Hash(String, DB::Any)` rows.
# Implements just enough of `DB::ResultSet` for the hydrator's `fetch_assoc` /
# `column_names` / `each` / `read` / `close` calls.
private class FakeResultSet < DB::ResultSet
  def initialize(@rows : Array(Hash(String, DB::Any)))
    statement = MockStatement.new(MockConnection.new, "")
    super(statement)
    @row_idx = -1
    @col_idx = 0
    @columns = @rows.empty? ? [] of String : @rows.first.keys
  end

  def move_next : Bool
    @row_idx += 1
    @col_idx = 0
    @row_idx < @rows.size
  end

  def column_count : Int32
    @columns.size
  end

  def column_name(index : Int32) : String
    @columns[index]
  end

  def read
    val = @rows[@row_idx][@columns[@col_idx]]
    @col_idx += 1
    val
  end

  def next_column_index : Int32
    @col_idx
  end
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
end
