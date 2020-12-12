require "./property"

module Athena::ORM::Mapping
  # TODO: Make this an abstract struct again
  module ColumnMetadata
    getter column_name : String
    getter table_name : String?
    getter type : AORM::Types::Type

    getter? is_primary_key : Bool
    getter? nilable : Bool

    def initialize(
      @column_name : String,
      @is_primary_key : Bool,
      @type : AORM::Types::Type,
      @table_name : String?,
      @nilable : Bool
    )
    end

    def set_value(entity : AORM::Entity, value : _) : Nil
      raise "BUG: Invoked default set_value"
    end

    def get_value(entity : AORM::Entity)
      raise "BUG: Invoked default get_value"
    end
  end

  abstract struct LocalColumnMetadata
    include ColumnMetadata

    getter value_generator : AORM::Mapping::ValueGeneratorMetadata?

    def initialize(
      column_name : String,
      is_primary_key : Bool,
      type : AORM::Types::Type,
      table_name : String?,
      nilable : Bool,
      @value_generator : AORM::Mapping::ValueGeneratorMetadata?
    )
      super column_name, is_primary_key, type, table_name, nilable
    end

    # TODO: Put length, scale, and precision ivars here

    def has_value_generator? : Bool
      !@value_generator.nil?
    end

    def value_generation_executor(platform : AORM::Platforms::Platform) : AORM::Sequencing::Executors::Interface?
      if generator = @value_generator
        AORM::Sequencing::Executors::ColumnValueGeneration.new self, generator.generator
      end
    end
  end

  struct FieldMetadata(IvarType, EntityType) < LocalColumnMetadata
    include Athena::ORM::Mapping::Property

    protected def self.build_metadata(
      context : ClassFactory::Context,
      name : String,
      class_metadata : ClassBase,
      column : Annotations::Column,
      id : Annotations::ID? = nil,
      generated_value : Annotations::GeneratedValue? = nil,
      sequence_generator : Annotations::SequenceGenerator? = nil
    ) : self
      is_primary_key = false
      value_generator = nil

      type = AORM::Types::Type.get_type(column.type_class || IvarType)

      if id
        is_primary_key = true

        if type.can_require_sql_conversion?
          # TODO: Use proper exception type
          raise "SQL Conversion not allowed for PK"
        end

        value_generator = generated_value.nil? ? nil : AORM::Mapping::ValueGeneratorMetadata.build_metadata(context, class_metadata, name, type, generated_value, sequence_generator)
      end

      new(
        column.name || name,
        is_primary_key,
        type,
        class_metadata.table_name,
        column.nilable,
        value_generator,
        name,
      )
    end

    # TODO: Add declaringClass ivar here when needed

    getter name : String
    getter entity_class : EntityType.class

    def initialize(
      column_name : String,
      is_primary_key : Bool,
      type : AORM::Types::Type,
      table_name : String?,
      nilable : Bool,
      value_generator : AORM::Mapping::ValueGeneratorMetadata?,
      @name : String,
      @entity_class : EntityType.class = EntityType
    )
      super column_name, is_primary_key, type, table_name, nilable, value_generator
    end

    def set_value(entity : EntityType, value : _) : Nil
      {% begin %}
        case self.column_name
          {% for column in EntityType.instance_vars %}
            when {{column.name.stringify}}
              if value.is_a? {{column.type}}
                pointerof(entity.@{{column.id}}).value = value
              end
          {% end %}
        end
      {% end %}
    end

    def get_value(entity : EntityType) : AORM::Mapping::Value
      {% begin %}
        case @name
          {% for column in EntityType.instance_vars %}
            when {{column.name.stringify}} then AORM::Mapping::ColumnValue.new {{column.name.stringify}}, entity.@{{column.id}}
          {% end %}
        else
          raise "BUG: Unknown column #{@name} within #{EntityType}"
        end
      {% end %}
    end
  end
end
