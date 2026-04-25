require "./type"

struct Athena::ORM::Types::BigInt < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(platform : AORM::Platforms::Platform) : ::String
    platform.big_int_type_declaration_sql
  end

  # :inherit:
  def to_db(value : _, platform : AORM::Platforms::Platform)
    value
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : Int64?
    case value
    when Nil then nil
    when Int then value.to_i64
    else          raise "BigInt cannot accept #{value.class}"
    end
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : Int64?
    value.read Int64?
  end
end
