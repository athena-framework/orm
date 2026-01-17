abstract struct Athena::ORM::Types::Type
  private BUILTIN_TYPES_MAP = {
    "string"  => AORM::Types::String,
    "text"    => AORM::Types::String,
    "integer" => AORM::Types::BigInt,
    "bigint"  => AORM::Types::BigInt,
    "boolean" => AORM::Types::Boolean,
  }

  class_getter type_registry : Athena::ORM::Types::TypeRegistry do
    instances = BUILTIN_TYPES_MAP.transform_values(&.new.as(AORM::Types::Type))
    AORM::Types::TypeRegistry.new(instances)
  end

  def self.get_type(name : ::String) : self
    self.type_registry.get(name)
  end

  def self.add_type(name : ::String, type : AORM::Types::Type) : Nil
    self.type_registry.register(name, type)
  end

  def self.has_type?(name : ::String) : Bool
    self.type_registry.has?(name)
  end

  def can_require_sql_conversion? : Bool
    false
  end

  def to_database_value_sql(sql_expression : ::String, platform : AORM::Platforms::Platform) : ::String
    sql_expression
  end

  abstract def sql_declaration(platform : AORM::Platforms::Platform) : ::String

  abstract def from_db(rs : DB::ResultSet, platform : AORM::Platforms::Platform)

  def to_db(value : _, platform : AORM::Platforms::Platform)
    value
  end
end
