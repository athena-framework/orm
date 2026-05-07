abstract class Athena::ORM::Platforms::Platform
  def quote_single_identifier(identifier : String) : String
    %("#{identifier.gsub('"', "\"\"")}")
  end

  def date_time_format_string : String
    "Y-m-d H:i:s"
  end

  def append_lock_hint(from_clause : String, lock_mode : LockMode) : String
    from_clause
  end

  def modify_limit_query(sql : String, limit : Int?, offset : Int = 0) : String
    if offset < 0
      raise "Offset must be a positive integer or zero, #{offset} given."
    end

    self.do_modify_limit_query sql, limit, offset
  end

  protected def do_modify_limit_query(sql : String, limit : Int?, offset : Int) : String
    sql += " LIMIT #{limit}" if limit
    sql += " OFFSET #{offset}" if offset && offset > 0

    sql
  end

  def sequence_next_value_sql(sequence_name : String) : String
    raise NotImplementedError.new {{@def.name.stringify}}
  end

  def empty_identity_insert_sql(quoted_table_name : String, quoted_identifier_column_name) : String
    "INSERT INTO #{quoted_table_name} (#{quoted_identifier_column_name}) VALUES (null)"
  end

  def supports_returning? : Bool
    false
  end

  def returning_keyword_sql : String
    "RETURNING"
  end

  # Passthrough by default: the underlying driver binds `Bool` natively against boolean columns (Postgres `BOOLEAN`, SQLite stored as `INTEGER 0/1`), so there's no value conversion to do at this layer. D
  def convert_booleans_to_db_value(value : Bool?) : Bool?
    value
  end

  def convert_booleans_to_db_value(value : Array(Bool)) : Array(Bool)
    value
  end

  def convert_booleans_to_db_value(value : _)
    raise "#{self.class} cannot convert #{value.class} to a boolean DB value"
  end

  def convert_from_boolean(value : Nil) : Nil
    nil
  end

  def convert_from_boolean(value : Bool) : Bool
    value
  end

  # SQLite stores booleans as `INTEGER 0/1`; map back to `Bool` here.
  # Crystal's `!!0` is `true` (only `nil`/`false` are falsy), so a literal `(bool)$value` port would silently convert `0` to `true` — explicit numeric comparison is required.
  def convert_from_boolean(value : Int) : Bool
    value != 0
  end

  def convert_from_boolean(value : _) : Bool
    raise "#{self.class} cannot convert #{value.class} to Bool"
  end

  # SQL Declarations

  def string_type_declaration_sql(column : Schema::Column) : String
    length = column.length

    unless column.fixed?
      return self.varchar_type_declaration_sql length
    end

    raise "TODO: Char type SQL"
  end

  def guid_type_declaration_sql(column : Schema::Column) : String
    column.length = 36
    column.fixed = true

    self.string_type_declaration_sql column
  end

  abstract def boolean_type_declaration_sql(column : Schema::Column) : String
  abstract def integer_type_declaration_sql(column : Schema::Column) : String
  abstract def big_int_type_declaration_sql(column : Schema::Column) : String

  private abstract def common_integer_type_declaration_sql(column : Schema::Column) : String

  private def varchar_type_declaration_sql(length : Int32?) : String
    raise "Length required" unless length

    "VARCHAR(#{length})"
  end

  # Limits / Constants

  # Maximum length of any given database identifier, like tables or column names.
  def max_identifier_length : Int32
    63
  end
end
