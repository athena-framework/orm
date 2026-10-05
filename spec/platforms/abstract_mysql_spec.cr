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
