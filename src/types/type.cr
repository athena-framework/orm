abstract struct Athena::ORM::Types::Type
  private BUILTIN_TYPES_MAP = {
    ::Bool   => AORM::Types::Boolean,
    ::Int64  => AORM::Types::BigInt,
    ::String => AORM::Types::String,
  }

  class_getter type_registry : Athena::ORM::Types::TypeRegistry do
    registry = AORM::Types::TypeRegistry.new

    BUILTIN_TYPES_MAP.each do |type, type_class|
      registry.add type, type_class.new
    end

    registry
  end

  def self.get_type(type_class) : self
    self.type_registry.get type_class
  end

  def self.add_type(type_class, type : AORM::Types::Type.class) : Nil
    self.type_registry.add type_class, type.new
  end

  # def self.get_type(type_class : AORM::Types::Type.class) : AORM::Types::Type
  # end

  def to_database_value_sql(sql_expression : ::String, platform : AORM::Platforms::Platform) : ::String
    sql_expression
  end

  abstract def sql_declaration(platform : AORM::Platforms::Platform) : ::String

  abstract def from_db(rs : DB::ResultSet, platform : AORM::Platforms::Platform)

  # abstract def name : String

  def to_db(value : _, platform : AORM::Platforms::Platform)
    value
  end
end
