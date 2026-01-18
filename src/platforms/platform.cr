abstract class Athena::ORM::Platforms::Platform
  def quote_single_identifier(identifier : String) : String
    %("#{identifier.gsub('"', "\"\"")}")
  end

  def append_lock_hint(from_clause : String, lock_mode : LockMode) : String
    from_clause
  end

  protected def modify_limit_query(sql : String, limit : Int?, offset : Int = 0) : String
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

  # Limits / Constants

  # Maximum length of any given database identifier, like tables or column names.
  def max_identifier_length : Int32
    63
  end
end
