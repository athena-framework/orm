require "./type"

# Holds decimal values as strings, so no precision is lost.
# Map a `BigDecimal` field with `Types::Number` instead to work with the values numerically.
struct Athena::ORM::Types::Decimal < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String
    platform.decimal_type_declaration_sql column
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : ::String?
    case value
    when Nil, ::String         then value
    when ::Bool, ::Time, Bytes then raise "Decimal cannot accept #{value.class}"
    else
      # SQLite can return a decimal column as a float or integer, and Postgres as a `PG::Numeric`.
      value.to_s
    end
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : ::String?
    self.to_crystal_value value.read, platform
  end
end
