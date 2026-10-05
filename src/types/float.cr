require "./type"

struct Athena::ORM::Types::Float < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String
    platform.float_declaration_sql column
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : Float64?
    case value
    when Nil                      then nil
    when ::Int, ::Float, ::String then value.to_f64
    else                               raise "Float cannot accept #{value.class}"
    end
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : Float64?
    self.to_crystal_value value.read, platform
  end
end
