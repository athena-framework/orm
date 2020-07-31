struct Athena::ORM::Platforms::Postgres < Athena::ORM::Platforms::Platform
  def name : String
    "postgresql"
  end

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

  def supports_schemas? : Bool
    true
  end
end
