# Common methods/properties required by both `AORM::Mapping::Column` and `AORM::Mapping::Association`.
module Athena::ORM::Mapping::Common(EntityType)
  getter name : String
  getter is_primary_key : Bool

  def initialize(
    @name : String,
    @is_primary_key : Bool
  )
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
