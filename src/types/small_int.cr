require "./type"

struct Athena::ORM::Types::SmallInt < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String
    platform.small_int_type_declaration_sql column
  end

  # Drivers can't bind `Int16`, so it's widened to `Int32`.
  def to_db(value : _, platform : AORM::Platforms::Platform)
    value.is_a?(Int16) ? value.to_i32 : value
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : Int16?
    case value
    when Nil                      then nil
    when ::Int, ::Float, ::String then value.to_i16
    else                               raise "SmallInt cannot accept #{value.class}"
    end
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : Int16?
    self.to_crystal_value value.read, platform
  end
end
