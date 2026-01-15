struct Athena::ORM::Mapping::Driver::Annotation
  def load_metadata_for_entity(metadata : Class(T)) : Nil forall T
    {% if ann = T.annotation AORMA::Entity %}
      entity_ann = AORM::Mapping::Annotations::Entity.new({{ann.named_args.double_splat}})

      if repo_class = entity_ann.repository_class
        metadata.custom_repository_class = repo_class
      end

      if entity_ann.read_only
        metadata.read_only = true
      end


    {% elsif T.annotation AORMA::MappedSuperclass %}
      # TODO: This
    {% elsif T.annotation AORMA::Embeddable %}
      # TODO: This
    {% else %}
      {% raise T.raise "Not valid entity or superclass" %}
    {% end %}

    primary_table = Hash(String, String | Bool | Nil).new

    {% if ann = T.annotation AORMA::Table %}
      table_ann = AORM::Mapping::Annotations::Table.new({{ann.named_args.double_splat}})
      primary_table["name"] = table_ann.name
      primary_table["schema"] = table_ann.schema

      # TODO: Support table options?
    {% end %}

    # TODO: Handle `Index` annotation

    # TODO: Handle `UniqueConstraint` annotation

    metadata.primary_table = primary_table

    # TODO: Handle `Cache` annotation

    # TODO: Handle `InheritanceType` annotation

    # TODO: Handle `ChangeTrackingPolicy` annotation

    {% for ivar in T.instance_vars %}
      {% if ann = ivar.annotation AORMA::Column %}
        column_ann = AORM::Mapping::Annotations::Column.new({{ann.named_args.double_splat}})

        pp column_ann
      {% end %}


    {% end %}

    # TODO: Handle `AssociationOverrides` annotation

    # TODO: Handle `AttributeOverrides` annotation

    # TODO: Handle `EntityListeners` annotation

    # TODO: Handle `HasLifecycleCallbacks` annotation
  end

  private def load(entity_class : T.class) : Nil forall T
  end
end
