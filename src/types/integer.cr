require "./type"

struct Athena::ORM::Types::Integer < Athena::ORM::Types::Type
  def sql_declaration(platform : AORM::Platforms::Platform) : ::String
    "INTEGER"
  end

  def to_db(value : _, platform : AORM::Platforms::Platform)
    value
  end

  def from_db(rs : DB::ResultSet, platform : AORM::Platforms::Platform) : Int32?
    rs.read Int32?
  end

  def to_crystal_value(value : Int64, platform : Platforms::Platform) : Int32
    value.to_i32
  end

  def to_crystal_value(value : Int32, platform : Platforms::Platform) : Int32
    value
  end

  def to_crystal_value(value : Nil, platform : Platforms::Platform) : Nil
    nil
  end
end
