abstract class Athena::ORM::Entity
  def self.entity_metadata_class : AORM::Mapping::ClassBase.class
    {% begin %}
      AORM::Mapping::Class({{@type}})
    {% end %}
  end

  macro inherited
    {% verbatim do %}
      # TODO: Extract this out of the entity itself.
      def self.from_rs(class_metadata : AORM::Mapping::ClassBase, rs : DB::ResultSet, platform : AORM::Platforms::Platform) : self
        {% begin %}
          instance = allocate
          class_metadata.each do |column|
            case column.name
            {% for column in @type.instance_vars.select &.annotation AORMA::Column %}
              when {{column.name.stringify}} then pointerof(instance.@{{column.id}}).value = column.type.from_db(rs, platform).as({{column.type}})
            {% end %}
            end
          end
          instance
        {% end %}
      end
    {% end %}
  end
end
