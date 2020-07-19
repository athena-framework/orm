require "./type"

abstract struct Athena::ORM::Types::Enum(T) < Athena::ORM::Types::Type
  def sql_declaration(platform : AORM::Platforms::Platform) : ::String
    platform.guid_type_declaration_sql
  end

  def to_db(value : _, platform : AORM::Platforms::Platform)
    value.to_s
  end

  def from_db(rs : DB::ResultSet, platform : AORM::Platforms::Platform? = nil) : T?
    return unless value = rs.read ::String?
    T.parse value
  end
end
