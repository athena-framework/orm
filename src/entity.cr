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
            {% for column in @type.instance_vars %}
              when {{column.name.stringify}}
                {% if column.type <= AORM::Entity? %}
                  return instance if property.as(AORM::Mapping::Association).is_owning_side?
                  association_class_metadata = em.class_metadata property.as(AORM::Mapping::Association).target_entity
                  value = association_class_metadata.entity_class.from_rs(em, association_class_metadata, rs, platform)
                  pointerof(instance.@{{column.id}}).value = value.as {{column.type}}
                {% else %}
                  value = property.as(AORM::Mapping::Column).type.from_db(rs, platform)
                  pointerof(instance.@{{column.id}}).value = value.as({{column.type}})
                {% end %}
            {% end %}
            end
          end
          instance
        {% end %}
      end
    {% end %}
  end
end
