abstract class Athena::ORM::Entity
  macro inherited
    {% verbatim do %}
      def self.from_rs(rs : DB::ResultSet) : self
        {% begin %}
          instance = allocate
          self.column_metadata.each do |column|
            case column.name
            {% for column in @type.instance_vars.select &.annotation AORM::Column %}
              when {{column.name.stringify}} then pointerof(instance.@{{column.id}}).value = column.type.from_db(rs).as({{column.type}})
            {% end %}
            end
          end
          instance
        {% end %}
      end

      # :nodoc:
      def self.entity_class_metadata : Athena::ORM::Metadata::Class
        {% begin %}
          class_metadata = Athena::ORM::Metadata::Class.new(
            entity_class: {{@type}},
            table: AORM::Metadata::Table.new({{@type.name.stringify + 's'}})
          )

          {% properties = [] of Nil %}

          {% for column in @type.instance_vars.select &.annotation AORM::Column %}
            {% ann = column.annotation AORM::Column %}
            {% type = ann[:type] == nil ? (column.type.union? ? column.type.union_types.first : column.type) : ann[:type] %}

            class_metadata.add_property(
              AORM::Metadata::Column({{column.type}}).new(
                {{column.name.id.stringify}},
                Athena::ORM::Types::Type.get_type({{type}}),
                {{column.type.nilable?}},
                {{!!column.annotation AORM::ID}},
                {{column.default_value}}
              )
            )
            
          {% end %}

          class_metadata
        {% end %}
      end
    {% end %}
  end
end

# def self.entity_class_metadata : Array(Athena::ORM::Metadata::ColumnBase)
#   {% begin %}
#     {% column_metadata = [] of Nil %}

#     {% for column in @type.instance_vars.select &.annotation AORM::Column %}
#       {% ann = column.annotation AORM::Column %}

#       {% type = ann[:type] == nil ? (column.type.union? ? column.type.union_types.first : column.type) : ann[:type] %}

#       {%
#         column_metadata << %(AORM::Metadata::Column(#{column.type}).new(
#           #{column.name.id.stringify},
#           Athena::ORM::Types::Type.get_type(#{type}),
#           #{column.type.nilable?},
#           #{!!column.annotation AORM::ID},
#           #{column.default_value}
#         )).id
#       %}
#     {% end %}

#     {{column_metadata}} of AORM::Metadata::ColumnBase
#   {% end %}
# end