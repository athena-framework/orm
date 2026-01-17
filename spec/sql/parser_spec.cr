require "../spec_helper"

describe Athena::ORM::SQL::Parser do
  describe "#parse" do
    it "detects positional parameters" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = ?", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = $1"
      visitor.parameter_map.should eq({1 => 1})
    end

    it "detects multiple positional parameters" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = ? AND b = ?", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = $1 AND b = $2"
      visitor.parameter_map.should eq({1 => 1, 2 => 2})
    end

    it "detects named parameters" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = :name", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = $1"
      visitor.parameter_map.should eq({":name" => 1})
    end

    it "detects multiple named parameters" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = :name AND b = :age", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = $1 AND b = $2"
      visitor.parameter_map.should eq({":name" => 1, ":age" => 2})
    end

    it "reuses position for repeated named parameters" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = :name OR b = :name", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = $1 OR b = $1"
      visitor.parameter_map.should eq({":name" => 1})
    end

    it "handles mixed positional and named parameters" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = ? AND b = :name", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = $1 AND b = $2"
      visitor.parameter_map.should eq({1 => 1, ":name" => 2})
    end

    it "ignores ? inside single-quoted strings" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = '?'", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = '?'"
      visitor.parameter_map.should be_empty
    end

    it "ignores :name inside single-quoted strings" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = ':name'", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = ':name'"
      visitor.parameter_map.should be_empty
    end

    it "ignores ? inside double-quoted identifiers" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse(%(SELECT * FROM "table?" WHERE a = ?), visitor)

      visitor.sql.should eq %(SELECT * FROM "table?" WHERE a = $1)
      visitor.parameter_map.should eq({1 => 1})
    end

    it "ignores ? inside backtick identifiers" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM `table?` WHERE a = ?", visitor)

      visitor.sql.should eq "SELECT * FROM `table?` WHERE a = $1"
      visitor.parameter_map.should eq({1 => 1})
    end

    it "ignores ? inside bracket identifiers" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM [table?] WHERE a = ?", visitor)

      visitor.sql.should eq "SELECT * FROM [table?] WHERE a = $1"
      visitor.parameter_map.should eq({1 => 1})
    end

    it "ignores ? inside single-line comments" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t -- WHERE a = ?\nWHERE b = ?", visitor)

      visitor.sql.should eq "SELECT * FROM t -- WHERE a = ?\nWHERE b = $1"
      visitor.parameter_map.should eq({1 => 1})
    end

    it "ignores ? inside multi-line comments" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t /* WHERE a = ? */ WHERE b = ?", visitor)

      visitor.sql.should eq "SELECT * FROM t /* WHERE a = ? */ WHERE b = $1"
      visitor.parameter_map.should eq({1 => 1})
    end

    it "handles escaped single quotes in strings" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = 'it''s a test' AND b = ?", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = 'it''s a test' AND b = $1"
      visitor.parameter_map.should eq({1 => 1})
    end

    it "handles complex SQL with multiple elements" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      sql = <<-SQL
        SELECT * FROM users
        WHERE name = :name -- filter by name
        AND age > ?
        AND status = 'active'
        /* multi-line
           comment with :param and ? */
        AND role = :role
        SQL

      parser.parse(sql, visitor)

      expected = <<-SQL
        SELECT * FROM users
        WHERE name = $1 -- filter by name
        AND age > $2
        AND status = 'active'
        /* multi-line
           comment with :param and ? */
        AND role = $3
        SQL

      visitor.sql.should eq expected
      visitor.parameter_map.should eq({":name" => 1, 1 => 2, ":role" => 3})
    end

    it "does not match ?? as a parameter" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a ?? 'key' AND b = ?", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a ?? 'key' AND b = $1"
      visitor.parameter_map.should eq({1 => 1})
    end

    it "handles SQL with no parameters" do
      visitor = Athena::ORM::SQL::ConvertParameters.new
      parser = Athena::ORM::SQL::Parser.new

      parser.parse("SELECT * FROM t WHERE a = 1", visitor)

      visitor.sql.should eq "SELECT * FROM t WHERE a = 1"
      visitor.parameter_map.should be_empty
    end

    describe "with MySQL string escaping" do
      it "handles backslash-escaped quotes in strings" do
        visitor = Athena::ORM::SQL::ConvertParameters.new
        parser = Athena::ORM::SQL::Parser.new(mysql_string_escaping: true)

        parser.parse("SELECT * FROM t WHERE a = 'it\\'s a test' AND b = ?", visitor)

        visitor.sql.should eq "SELECT * FROM t WHERE a = 'it\\'s a test' AND b = $1"
        visitor.parameter_map.should eq({1 => 1})
      end
    end
  end
end
