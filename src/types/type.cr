module Athena::ORM::Types
  BIGINT     = "bigint"
  BINARY     = "binary"
  BLOB       = "blob"
  BOOLEAN    = "boolean"
  DATETIME   = "datetime"
  DECIMAL    = "decimal"
  FLOAT      = "float"
  GUID       = "guid"
  INTEGER    = "integer"
  NUMBER     = "number"
  SMALLFLOAT = "smallfloat"
  SMALLINT   = "smallint"
  STRING     = "string"
  TEXT       = "text"

  abstract struct Type
    # Crystal types are mapped to ORM types in `src/mapping/class.cr`
    private BUILTIN_TYPES_MAP = {
      Types::STRING     => AORM::Types::String,
      Types::TEXT       => AORM::Types::String,
      Types::INTEGER    => AORM::Types::Integer,
      Types::SMALLINT   => AORM::Types::SmallInt,
      Types::BIGINT     => AORM::Types::BigInt,
      Types::FLOAT      => AORM::Types::Float,
      Types::SMALLFLOAT => AORM::Types::SmallFloat,
      Types::DECIMAL    => AORM::Types::Decimal,
      Types::BOOLEAN    => AORM::Types::Boolean,
      Types::DATETIME   => AORM::Types::Datetime,
      Types::GUID       => AORM::Types::Guid,
      Types::BINARY     => AORM::Types::Binary,
      Types::BLOB       => AORM::Types::Blob,
    }

    class_getter type_registry : Athena::ORM::Types::TypeRegistry do
      registry = AORM::Types::TypeRegistry.new(BUILTIN_TYPES_MAP.transform_values(&.new.as(AORM::Types::Type)))

      {% if @top_level.has_constant?("BigDecimal") %}
        registry.register Types::NUMBER, AORM::Types::Number.new
      {% end %}

      registry
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
    # A subclass whose `to_crystal_value` takes `value : _` must define this overload as well, since that one would otherwise also receive the result set.
    # It can skip the union-type dispatch when a concrete `rs.read T` is available — for example `Integer` reads `rs.read Int32?` directly.
    #
    # Note: this advances the cursor by one column.
    def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform)
      self.to_crystal_value value.read, platform
    end

    # Crystal value to its DB representation
    def to_db(value : _, platform : AORM::Platforms::Platform)
      value
    end

    # Reads the next column with this type, boxing values that are neither driver scalars nor ORM references.
    # Called on each concrete type, so its own `#to_crystal_value` return type is what gets boxed.
    def read_value(rs : DB::ResultSet, platform : Platforms::Platform) : Mapping::ValueAny
      Mapping.box self.to_crystal_value(rs, platform)
    end
  end
end
