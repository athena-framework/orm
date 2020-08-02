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

    @value_generator : AORM::Mapping::ValueGeneratorMetadata? = nil

    def initialize(
      @name : String,
      class_metadata : AORM::Mapping::Class,
      column : AORM::Mapping::Annotations::Column,
      id : AORM::Mapping::Annotations::ID? = nil,
      generated_value : AORM::Mapping::Annotations::GeneratedValue? = nil,
      sequence_generator : AORM::Mapping::Annotations::SequenceGenerator? = nil,
      @entity_class : EntityType.class = EntityType
    )
      @type = column.type || AORM::Types::Type.get_type IvarType

      @column_name = column.name || @name
      @table_name = class_metadata.table_name

      @column_definition = column.column_definition
      @scale = column.scale
      @precision = column.precision
      @length = column.length
      @nilable = column.nilable
      @unique = column.unique

      if id
        @is_primary_key = true

        if @type.can_require_sql_conversion?
          # TODO: Use proper exception type
          raise "SQL Conversion not allowed for PK"
        end

        @value_generator = AORM::Mapping::ValueGeneratorMetadata.from_annotations(
          @name,
          generated_value,
          sequence_generator
        )
      end
    end

    def has_value_generator? : Bool
      !@value_generator.nil?
    end

    def value_generation_executor : AORM::Sequencing::Executors::Interface?
      # TODO: Pass in the platform to this method

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
