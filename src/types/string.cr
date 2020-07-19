require "./type"

struct Athena::ORM::Types::String < Athena::ORM::Types::Type
  def sql_declaration(platform : AORM::Platforms::Platform) : ::String
    platform.varchar_type_declaration_sql
  end

  def to_db(value : _, platform : AORM::Platforms::Platform)
    value.to_s
  end

  def from_db(rs : DB::ResultSet, platform : AORM::Platforms::Platform? = nil) : ::String?
    rs.read ::String?
  end
end
