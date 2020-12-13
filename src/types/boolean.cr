require "./type"

struct Athena::ORM::Types::Boolean < Athena::ORM::Types::Type
  def sql_declaration(platform : AORM::Platforms::Platform) : ::String
    platform.boolean_type_declaration_sql
  end

  def to_db(value : _, platform : AORM::Platforms::Platform)
    false
  end

  def from_db(rs : DB::ResultSet, platform : AORM::Platforms::Platform) : Bool?
    rs.read Bool?
  end
end
