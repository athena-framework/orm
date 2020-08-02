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

  record Column(DefaultType, EntityType) < Athena::ORM::Mapping::ColumnBase,
    name : String,
    type : AORM::Types::Type,
    nullable : Bool = false,
    is_primary_key : Bool = false,
    default : DefaultType? = nil,
    value_generator : AORM::Mapping::ValueGeneratorMetadata? = nil,
    entity_class : EntityType.class = EntityType do
    def column_name : String
      # TODO: support reading column name off annotation
      @name
    end

    def table_name : String?
      # TODO: Set this when building the property
      "users"
    end

    def has_value_generator? : Bool
      !@value_generator.nil?
    end

    def value_generation_executor : AORM::ValueGenerationExecutorInterface?
      # TODO: Pass in the platform to this method

      if generator = @value_generator
        AORM::ColumnValueGeneratorExecutor.new self, generator.generator
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
