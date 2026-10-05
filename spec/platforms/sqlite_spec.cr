require "../spec_helper"

struct SQLitePlatformDeclarationTest < ASPEC::TestCase
  @platform : AORM::Platforms::SQLite = AORM::Platforms::SQLite.new

  def test_numeric_declarations : Nil
    @platform.small_int_type_declaration_sql(column).should eq "SMALLINT"
    @platform.float_declaration_sql(column).should eq "DOUBLE PRECISION"
    @platform.small_float_declaration_sql(column).should eq "REAL"
  end

  # SQLite only auto-increments `INTEGER PRIMARY KEY` columns.
  def test_auto_increment_small_int_is_declared_as_integer : Nil
    @platform.small_int_type_declaration_sql(column auto_increment: true).should start_with "INTEGER"
  end

  def test_binary_declarations_are_blob : Nil
    @platform.blob_type_declaration_sql(column).should eq "BLOB"
    @platform.binary_type_declaration_sql(column length: 16).should eq "BLOB"
  end

  private def column(*, length : Int32? = nil, auto_increment : Bool = false) : AORM::Schema::Column
    AORM::Schema::Column.new("c", AORM::Types::Type.get_type("string")).tap do |c|
      c.length = length
      c.auto_increment = auto_increment
    end
  end
end
