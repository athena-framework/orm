abstract class Athena::ORM::Entity
  macro inherited
    {% verbatim do %}
      def self.from_rs(rs : DB::ResultSet, platform : AORM::Platforms::Platform) : self
        {% begin %}
          instance = allocate
          self.entity_class_metadata.each do |column|
            case column.name
            {% for column in @type.instance_vars.select &.annotation AORMA::Column %}
              when {{column.name.stringify}} then pointerof(instance.@{{column.id}}).value = column.type.from_db(rs, platform).as({{column.type}})
            {% end %}
            end
          end
          instance
        {% end %}
      end

      class_getter entity_class_metadata : AORM::Mapping::ClassBase do
        {% begin %}
          AORM::Mapping::Class({{@type}}).new
        {% end %}
      end
    {% end %}
  end
end
