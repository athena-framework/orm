abstract class Athena::ORM::Entity
  def self.entity_metadata_class : AORM::Mapping::ClassBase.class
    {% begin %}
      AORM::Mapping::Class({{@type}})
    {% end %}
  end

  macro inherited
    {% verbatim do %}
      # TODO: Extract this out of the entity itself.
      def self.from_rs(em : AORM::EntityManagerInterface, class_metadata, rs : DB::ResultSet, platform : AORM::Platforms::Platform)
        {% begin %}
          instance = allocate
          class_metadata.each do |property|
            case property.name
            {% for column in @type.instance_vars.select &.annotation AORMA::Column %}
              when {{column.name.stringify}}
                pointerof(instance.@{{column.id}}).value = property.as(AORM::Mapping::ColumnMetadata).type.from_db(rs, platform).as({{column.type}})
            {% end %}
            end
          end
          instance
        {% end %}
      end
    {% end %}
  end
end
