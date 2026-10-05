require "./type"

struct Athena::ORM::Types::SmallFloat < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String
    platform.small_float_declaration_sql column
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : Float32?
    case value
    when Nil                      then nil
    when ::Int, ::Float, ::String then value.to_f32
    else                               raise "SmallFloat cannot accept #{value.class}"
    end
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : Float32?
    self.to_crystal_value value.read, platform
  end
end
