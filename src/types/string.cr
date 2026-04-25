require "./type"

struct Athena::ORM::Types::String < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(platform : AORM::Platforms::Platform) : ::String
    platform.varchar_type_declaration_sql
  end

  # :inherit:
  def to_db(value : _, platform : AORM::Platforms::Platform)
    value.to_s
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : ::String?
    case value
    when Nil      then nil
    when ::String then value
    else               value.to_s
    end
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : ::String?
    value.read ::String?
  end
end
