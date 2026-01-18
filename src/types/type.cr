module Athena::ORM::Types
  BIGINT     = "bigint"
  BOOLEAN    = "boolean"
  FLOAT      = "float"
  INTEGER    = "integer"
  SMALLFLOAT = "smallfloat"
  SMALLINT   = "smallint"
  STRING     = "string"
  TEXT       = "text"

  abstract struct Type
    private BUILTIN_TYPES_MAP = {
      Types::STRING  => AORM::Types::String,
      Types::TEXT    => AORM::Types::String,
      Types::INTEGER => AORM::Types::BigInt,
      Types::BIGINT  => AORM::Types::BigInt,
      Types::BOOLEAN => AORM::Types::Boolean,
    }

    class_getter type_registry : Athena::ORM::Types::TypeRegistry do
      AORM::Types::TypeRegistry.new(BUILTIN_TYPES_MAP.transform_values(&.new.as(AORM::Types::Type)))
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

    def self.override_type(name : ::String, type : AORM::Types::Type) : Nil
      self.type_registry.override name, type
    end

    def self.type_map : Hash(::String, AORM::Types::Type.class)
      self.type_registry.instances.transform_values(&.class)
    end

    # Modifies the SQL expression (identifier, parameter) to convert to a Crystal value
    def from_db_sql(sql_expression : ::String, platform : AORM::Platforms::Platform) : ::String
      sql_expression
    end

    # Modifies the SQL expression (identifier, parameter) to convert to a database value
    def to_db_sql(sql_expression : ::String, platform : AORM::Platforms::Platform) : ::String
      sql_expression
    end

    # The SQL used to declare a column of this type
    abstract def sql_declaration(platform : AORM::Platforms::Platform) : ::String

    # Extracts/converts a value from *rs* into a Crystal value
    abstract def from_db(rs : DB::ResultSet, platform : AORM::Platforms::Platform)

    def to_crystal_value(value : _, platform : Platforms::Platform)
      value
    end

    # Crystal value to its DB representation
    def to_db(value : _, platform : AORM::Platforms::Platform)
      value
    end
  end
end
