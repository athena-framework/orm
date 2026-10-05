require "../spec_helper"

struct AbstractMySQLPlatformTest < ASPEC::TestCase
  @[DataProvider("server_version_provider")]
  def test_for_server_version(server_version : String, platform : AORM::Platforms::AbstractMySQL.class) : Nil
    AORM::Platforms::AbstractMySQL.for_server_version(server_version).class.should eq platform
  end

  def server_version_provider : Hash
    {
      "MySQL"                      => {"8.4.9", AORM::Platforms::MySQL},
      "MariaDB"                    => {"12.2.2-MariaDB-ubu2404", AORM::Platforms::Maria},
      "MariaDB with 5.5.5- prefix" => {"5.5.5-10.11.6-MariaDB-0+deb12u1", AORM::Platforms::Maria},
      "lowercase mariadb"          => {"10.6.12-mariadb", AORM::Platforms::Maria},
    }
  end

  def test_mysql_does_not_support_returning : Nil
    AORM::Platforms::MySQL.new.supports_returning?.should be_false
  end

  # Without `ANSI_QUOTES`, MySQL and MariaDB read a double-quoted name as a string literal.
  def test_quote_single_identifier_uses_backticks : Nil
    AORM::Platforms::MySQL.new.quote_single_identifier("groups").should eq "`groups`"
    AORM::Platforms::Maria.new.quote_single_identifier("groups").should eq "`groups`"
  end

  def test_quote_single_identifier_escapes_backticks : Nil
    AORM::Platforms::MySQL.new.quote_single_identifier("we`ird").should eq "`we``ird`"
  end
end

struct MySQLPlatformDeclarationTest < ASPEC::TestCase
  @platform : AORM::Platforms::MySQL = AORM::Platforms::MySQL.new

  def test_numeric_declarations : Nil
    @platform.small_int_type_declaration_sql(column).should eq "SMALLINT"
    @platform.float_declaration_sql(column).should eq "DOUBLE PRECISION"
    @platform.small_float_declaration_sql(column).should eq "FLOAT"
    @platform.decimal_type_declaration_sql(column precision: 10, scale: 2).should eq "NUMERIC(10, 2)"
  end

  def test_numeric_declarations_can_be_unsigned : Nil
    @platform.small_int_type_declaration_sql(column unsigned: true).should eq "SMALLINT UNSIGNED"
    @platform.float_declaration_sql(column unsigned: true).should eq "DOUBLE PRECISION UNSIGNED"
    @platform.decimal_type_declaration_sql(column precision: 10, scale: 2, unsigned: true).should eq "NUMERIC(10, 2) UNSIGNED"
  end

  @[DataProvider("blob_lengths")]
  def test_blob_declaration_fits_the_length(length : Int32?, declaration : String) : Nil
    @platform.blob_type_declaration_sql(column length: length).should eq declaration
  end

  def blob_lengths : Hash
    {
      "no length" => {nil, "LONGBLOB"},
      "tiny"      => {255, "TINYBLOB"},
      "regular"   => {65_535, "BLOB"},
      "medium"    => {16_777_215, "MEDIUMBLOB"},
      "long"      => {16_777_216, "LONGBLOB"},
    }
  end

  def test_binary_declaration : Nil
    @platform.binary_type_declaration_sql(column length: 16).should eq "VARBINARY(16)"
    @platform.binary_type_declaration_sql(column length: 16, fixed: true).should eq "BINARY(16)"
  end

  def test_varbinary_declaration_requires_a_length : Nil
    expect_raises(Exception, "Length required") { @platform.binary_type_declaration_sql column }
  end

  private def column(*, length : Int32? = nil, precision : Int32? = nil, scale : Int32? = nil, unsigned : Bool = false, fixed : Bool = false) : AORM::Schema::Column
    AORM::Schema::Column.new("c", AORM::Types::Type.get_type("string")).tap do |c|
      c.length = length
      c.precision = precision
      c.scale = scale
      c.unsigned = unsigned
      c.fixed = fixed
    end
  end
end
