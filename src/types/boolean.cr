require "./type"

struct Athena::ORM::Types::Boolean < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(platform : AORM::Platforms::Platform) : ::String
    platform.boolean_type_declaration_sql
  end

  # :inherit:
  def to_db(value : _, platform : AORM::Platforms::Platform)
    false
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : Bool?
    # TODO: Move this into `Platform`
    case value
    when Nil  then nil
    when Bool then value
    when Int  then value != 0 # SQLite stores booleans as 0/1.
    else           raise "Boolean cannot accept #{value.class}"
    end
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : Bool?
    value.read Bool?
  end
end
