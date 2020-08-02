require "./column"
require "./table"

module Athena::ORM::Mapping
  abstract struct ColumnBase
    def set_value(entity : AORM::Entity, value : _) : Nil
    end

    def get_value(entity : AORM::Entity)
      raise "BUG: Invoked default get_value"
    end
  end

  struct Column(IvarType, EntityType) < Athena::ORM::Mapping::ColumnBase
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

        value_generator = AORM::Mapping::ValueGeneratorMetadata.build_metadata(context, class_metadata, name, type, generated_value, sequence_generator)
      end

      new(
        name,
        type,
        column.name || name,
        is_primary_key,
        class_metadata.table_name,
        column.column_definition,
        column.scale,
        column.precision,
        column.length,
        column.nilable,
        column.unique,
        value_generator
      )
    end

    getter name : String
    getter type : AORM::Types::Type

    getter default : IvarType? = nil

    getter column_name : String
    getter is_primary_key : Bool = false
    getter value_generator : AORM::Mapping::ValueGeneratorMetadata?
    getter entity_class : EntityType.class
    getter table_name : String?

    # TODO: Maybe break these out to share with a type for migrations/generation?
    getter column_definition : String?
    getter scale : Int32
    getter precision : Int32
    getter length : Int32
    getter? nilable : Bool
    getter? unique : Bool
    getter? versioned : Bool = false

    def initialize(
      @name : String,
      @type : AORM::Types::Type,
      @column_name : String,
      @is_primary_key : Bool,
      @table_name : String?,
      @column_definition : String?,
      @scale : Int32,
      @precision : Int32,
      @length : Int32,
      @nilable : Bool,
      @unique : Bool,
      @value_generator : ValueGeneratorMetadata?,
      @entity_class : EntityType.class = EntityType
    )
    end

    def has_value_generator? : Bool
      !@value_generator.nil?
    end

    def value_generation_executor(platform : AORM::Platforms::Platform) : AORM::Sequencing::Executors::Interface?
      if generator = @value_generator
        AORM::Sequencing::Executors::ColumnValueGeneration.new self, generator.generator
      end
    end

    def set_value(entity : EntityType, value : _) : Nil
      {% begin %}
        case self.column_name
          {% for column in EntityType.instance_vars.select &.annotation AORMA::Column %}
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
        {% for column in EntityType.instance_vars.select &.annotation AORMA::Column %}
          case @name
            {% for column in EntityType.instance_vars.select &.annotation AORMA::Column %}
              when {{column.name.stringify}} then AORM::Mapping::ColumnValue.new {{column.name.stringify}}, entity.@{{column.id}}
            {% end %}
          else
            raise "BUG: Unknown column"
          end
        {% end %}
      {% end %}
    end
  end
end
