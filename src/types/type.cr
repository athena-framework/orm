module Athena::ORM::Types
  BIGINT     = "bigint"
  BOOLEAN    = "boolean"
  DATETIME   = "datetime"
  FLOAT      = "float"
  INTEGER    = "integer"
  SMALLFLOAT = "smallfloat"
  SMALLINT   = "smallint"
  STRING     = "string"
  TEXT       = "text"

  abstract struct Type
    # Crystal types are mapped to ORM types in `src/mapping/class.cr`
    private BUILTIN_TYPES_MAP = {
      Types::STRING   => AORM::Types::String,
      Types::TEXT     => AORM::Types::String,
      Types::INTEGER  => AORM::Types::Integer,
      Types::BIGINT   => AORM::Types::BigInt,
      Types::BOOLEAN  => AORM::Types::Boolean,
      Types::DATETIME => AORM::Types::Datetime,
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
    abstract def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String

    # Converts a raw DB value into the Crystal type this `Type` represents.
    # Each subclass defines this once; it is the canonical place for any per-type translation logic (parsing, narrowing, decoding, etc.).
    # Accepts any input shape (matches Doctrine's `convertToPHPValue($value mixed)`)
    # and validates inside the body via `case value`.
    abstract def to_crystal_value(value : _, platform : Platforms::Platform)

    # Reads the next column from *value* with this `Type`'s target Crystal type.
    #
    # The default implementation does an untyped read and routes through `to_crystal_value(value, platform)`.
    # Subclasses MAY override to skip the union-type dispatch when a concrete `rs.read T` is available — for example `Integer` reads `rs.read Int32?` directly.
    #
    # Note: this advances the cursor by one column.
    def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform)
      self.to_crystal_value value.read, platform
    end

    # Crystal value to its DB representation
    def to_db(value : _, platform : AORM::Platforms::Platform)
      value
    end
  end
end
