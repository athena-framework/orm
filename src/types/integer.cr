require "./type"

struct Athena::ORM::Types::Integer < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String
    platform.integer_type_declaration_sql column
  end

  # :inherit:
  def to_db(value : _, platform : AORM::Platforms::Platform)
    value
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : Int32?
    case value
    when Nil                  then nil
    when Int, ::String, Float then value.to_i32
    else                           raise "Integer cannot accept #{value.class}"
    end
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : Int32?
    value.read Int32?
  end
end
