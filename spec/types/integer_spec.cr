require "../spec_helper"

struct IntegerTypeTest < ASPEC::TestCase
  def test_to_crystal_value_narrows_int64_to_int32 : Nil
    # Most DB drivers report integer columns as Int64; entity properties are
    # typically Int32. The Integer type does the narrowing on read.
    AORM::Types::Integer.new.to_crystal_value(42_i64, AORM::Platforms::SQLite.new).should eq 42_i32
  end

  def test_to_crystal_value_passes_int32_through : Nil
    AORM::Types::Integer.new.to_crystal_value(7_i32, AORM::Platforms::SQLite.new).should eq 7_i32
  end

  def test_to_crystal_value_preserves_nil : Nil
    AORM::Types::Integer.new.to_crystal_value(nil, AORM::Platforms::SQLite.new).should be_nil
  end

  def test_sql_declaration_returns_integer : Nil
    AORM::Types::Integer.new.sql_declaration(AORM::Platforms::SQLite.new).should eq "INTEGER"
  end

  # The RS overload is the hot path used by the hydrator. Integer overrides it
  # to do `rs.read Int32?` directly (skipping the union-type dispatch).
  def test_to_crystal_value_with_result_set_reads_typed_int32 : Nil
    rs = FakeResultSet.new([{"x" => 99_i32.as(DB::Any)}])
    rs.move_next

    AORM::Types::Integer.new.to_crystal_value(rs, AORM::Platforms::SQLite.new).should eq 99_i32
  end

  def test_to_crystal_value_with_result_set_preserves_nil : Nil
    rs = FakeResultSet.new([{"x" => nil.as(DB::Any)}])
    rs.move_next

    AORM::Types::Integer.new.to_crystal_value(rs, AORM::Platforms::SQLite.new).should be_nil
  end
end
