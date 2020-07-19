require "./type"

struct Athena::ORM::Types::BigInt < Athena::ORM::Types::Type
  def sql_declaration(platform : AORM::Platforms::Platform) : ::String
    platform.big_int_type_declaration_sql
  end

  def to_db(value : _, platform : AORM::Platforms::Platform)
    1_i64
  end

  def from_db(rs : DB::ResultSet, platform : AORM::Platforms::Platform? = nil) : Int64?
    rs.read Int64?
  end
end
