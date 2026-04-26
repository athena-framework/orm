require "./type"

abstract struct Athena::ORM::Types::Enum(T) < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String
    platform.guid_type_declaration_sql column
  end

  # :inherit:
  def to_db(value : _, platform : AORM::Platforms::Platform)
    value.to_s
  end

  # TODO: Enum parsing — current behavior just hands back the raw string.
  # The entity hydration pass is what currently turns the string back into a `T`.
  def to_crystal_value(value : _, platform : Platforms::Platform)
    value
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform)
    value.read ::String?
  end
end
