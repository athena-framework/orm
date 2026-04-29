require "./platform"

# Base platform for MySQL-like platforms.
abstract class Athena::ORM::Platforms::AbstractMySQL < Athena::ORM::Platforms::Platform
  # :inherit:
  def boolean_type_declaration_sql(column : Schema::Column) : String
    "TINYINT"
  end

  # :inherit:
  def integer_type_declaration_sql(column : Schema::Column) : String
    "INTEGER #{self.common_integer_type_declaration_sql column}"
  end

  # :inherit:
  def big_int_type_declaration_sql(column : Schema::Column) : String
    "BIGINT #{self.common_integer_type_declaration_sql column}"
  end

  private def common_integer_type_declaration_sql(column : Schema::Column) : String
    sql = self.unsigned_declaration column

    if column.auto_increment?
      sql = "#{sql} AUTO_INCREMENT"
    end

    sql
  end
end
