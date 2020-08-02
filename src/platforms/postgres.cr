struct Athena::ORM::Platforms::Postgres < Athena::ORM::Platforms::Platform
  def name : String
    "postgresql"
  end

  # TYPES

  def big_int_type_declaration_sql : String
    "BIGINT"
  end

  def boolean_type_declaration_sql : String
    "BOOLEAN"
  end

  def guid_type_declaration_sql : String
    "UUID"
  end

  def integer_type_declaration_sql : String
    "INT"
  end

  def small_int_type_declaration_sql : String
    "SMALLINT"
  end

  def sequence_next_val_sql(sequence_name : String) : String
    "SELECT NEXTVAL('#{sequence_name}')"
  end

  # IDENTIFIERS

  def sql_result_casing(column : String) : String
    column.downcase
  end

  # :inherit:
  #
  # Replaces `?` placeholders with indexed `$n placeholders.
  def modify_sql_placeholders(sql : String) : String
    return sql unless sql.includes? '?'

    idx = 1
    sql.gsub(/\?/) { "$#{idx}".tap { idx += 1 } }
  end

  # FEATURE SUPPORT

  def prefers_sequences? : Bool
    true
  end

  def supports_schemas? : Bool
    true
  end

  def uses_sequence_emulated_identity_columns? : Bool
    true
  end
end
