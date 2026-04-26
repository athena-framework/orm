require "./type"

struct Athena::ORM::Types::Boolean < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String
    platform.boolean_type_declaration_sql column
  end

  # :inherit:
  def to_db(value : _, platform : AORM::Platforms::Platform)
    platform.convert_booleans_to_db_value(value)
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : Bool?
    platform.convert_from_boolean(value)
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : Bool?
    value.read Bool?
  end
end
