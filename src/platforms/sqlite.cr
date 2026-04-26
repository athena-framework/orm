# Base platform for SQLite.
class Athena::ORM::Platforms::SQLite < Athena::ORM::Platforms::Platform
  def boolean_type_declaration_sql(column : Schema::Column) : String
    "BOOLEAN"
  end

  def integer_type_declaration_sql(column : Schema::Column) : String
    "INTEGER #{self.common_integer_type_declaration_sql column}"
  end

  def big_int_type_declaration_sql(column : Schema::Column) : String
    # SQLite autoincrement is implicit for INTEGER PKs, but not for BIGINT fields.
    if column.auto_increment?
      return self.integer_type_declaration_sql column
    end

    "BIGINT #{self.common_integer_type_declaration_sql column}"
  end

  private def common_integer_type_declaration_sql(column : Schema::Column) : String
    if column.auto_increment?
      return " PRIMARY KEY AUTOINCREMENT"
    end

    column.unsigned? ? " UNSIGNED" : ""
  end

  protected def do_modify_limit_query(sql : String, limit : Int?, offset : Int) : String
    if limit.nil? && offset > 0
      limit = -1
    end

    super sql, limit, offset
  end
end
