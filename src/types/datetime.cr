require "./type"

struct Athena::ORM::Types::Datetime < Athena::ORM::Types::Type
  # :inherit:
  def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String
    platform.string_type_declaration_sql column
  end

  # :inherit:
  def to_db(value : _, platform : AORM::Platforms::Platform)
    value
  end

  # :inherit:
  def to_crystal_value(value : _, platform : Platforms::Platform) : ::Time?
    return value if value.is_a?(::Time?)

    raise "Datetime cannot accept #{value.class}" unless value.is_a? ::String

    ::Time.parse_utc platform.date_time_format_string, value
  end

  # :inherit:
  def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : ::Time?
    value.read ::Time?
  end
end
