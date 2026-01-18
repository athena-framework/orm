# Base platform for Postgres.
class Athena::ORM::Platforms::Postgres < Athena::ORM::Platforms::Platform
  def sequence_next_value_sql(sequence_name : String) : String
    "SELECT NEXTVAL('#{sequence_name}')"
  end

  def empty_identity_insert_sql(quoted_table_name : String, quoted_identifier_column_name) : String
    "INSERT INTO #{quoted_table_name} (#{quoted_identifier_column_name}) VALUES (DEFAULT)"
  end
end
