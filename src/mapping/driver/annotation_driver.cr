module Athena::ORM::Mapping::Driver
  # These structs map to what Doctrine uses assoc arrays for but these are easier to work with.
  # Also don't want to use the annotation records directly either

  record TableMapping,
    name : String? = nil,
    schema : String? = nil,
    quoted : Bool? = nil

  record ColumnMapping,
    field_name : String,
    type : String? = nil,
    column_name : String? = nil,
    length : Int32? = nil,
    precision : Int32? = nil,
    scale : Int32? = nil,
    unique : Bool? = nil,
    nullable : Bool? = nil,
    not_insertable : Bool? = nil,
    not_updatable : Bool? = nil,
    enum_type : String? = nil,
    column_definition : String? = nil,
    generated : String? = nil,
    index : Bool = false,
    id : Bool? = nil,
    quoted : Bool? = nil,
    source_entity : AORM::Entity.class | Nil = nil,
    target_entity : AORM::Entity.class | Nil = nil,
    join_columns : Array(String)? = nil,
    inversed_by : String? = nil,
    mapped_by : String? = nil,
    cascade : Array(String)? = nil,
    orphan_removal : Bool? = nil,
    fetch_mode : FetchMode? = nil,
    is_owning_side : Bool? = nil,
    join_table : Hash(String, String)? = nil

  struct Annotation
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
        {% raise T.raise "'#{T}' is not a valid entity or superclass" unless T == AORM::Entity %}
      {% end %}

      primary_table = nil

      {% if ann = T.annotation AORMA::Table %}
        table_ann = AORM::Mapping::Annotations::Table.new({{ann.named_args.double_splat}})
        primary_table = TableMapping.new table_ann.name, table_ann.schema

        # TODO: Support table options?
      {% end %}

      # TODO: Handle `Index` annotation

      # TODO: Handle `UniqueConstraint` annotation

      if primary_table
        metadata.primary_table = primary_table
      end

      # TODO: Handle `Cache` annotation

      # TODO: Handle `InheritanceType` annotation

      # TODO: Handle `ChangeTrackingPolicy` annotation

      {% for ivar, idx in T.instance_vars %}
        mapping = ColumnMapping.new field_name: {{ivar.name.id.stringify}}

        {% if ann = ivar.annotation AORMA::Column %}
          mapping = self.column_ann_to_mapping {{ivar.name.id.stringify}}, AORM::Mapping::Annotations::Column.new({{ann.named_args.double_splat}})

          {% if ivar.annotation AORMA::ID %}
            mapping = mapping.copy_with id: true
          {% end %}

          {% if ann = ivar.annotation AORMA::GeneratedValue %}
            metadata.id_generator_type = AORM::Mapping::Annotations::GeneratedValue.new({{ann.named_args.double_splat}}).strategy
          {% end %}

          # TODO: Handle `Version` annotation

          metadata.map_field mapping
        {% elsif ann = ivar.annotation AORMA::OneToOne %}
          one_to_one_ann = AORM::Mapping::Annotations::OneToOne.new({{ann.named_args.double_splat}})

          if metadata.embedded_class?
            raise "Can't use OneToOne on embedded class"
          end

          {% if ivar.annotation AORMA::ID %}
            mapping = mapping.copy_with id: true
          {% end %}

          mapping = mapping.copy_with(
            target_entity: one_to_one_ann.target_entity,
            join_columns: [] of String,
            mapped_by: one_to_one_ann.mapped_by,
            inversed_by: one_to_one_ann.inversed_by,
            cascade: one_to_one_ann.cascade,
            orphan_removal: one_to_one_ann.orphan_removal,
            fetch_mode: one_to_one_ann.fetch_mode
          )

          metadata.map_one_to_one mapping
        {% end %}
      {% end %}

      # TODO: Handle `AssociationOverrides` annotation

      # TODO: Handle `AttributeOverrides` annotation

      # TODO: Handle `EntityListeners` annotation

      # TODO: Handle `HasLifecycleCallbacks` annotation
    end

    private def load(entity_class : T.class) : Nil forall T
    end

    private def column_ann_to_mapping(field_name : String, ann : AORM::Mapping::Annotations::Column) : ColumnMapping
      mapping = ColumnMapping.new(
        field_name: field_name,
        type: ann.type,
        scale: ann.scale,
        length: ann.length,
        precision: ann.precision,
        unique: ann.unique,
        nullable: ann.nullable,
        index: ann.index,
      )

      if value = ann.name
        mapping = mapping.copy_with column_name: value
      end

      if value = ann.column_definition
        mapping = mapping.copy_with column_definition: value
      end

      if ann.updatable == false
        mapping = mapping.copy_with not_updatable: true
      end

      if ann.insertable == false
        mapping = mapping.copy_with not_insertable: true
      end

      if value = ann.generated
        mapping = mapping.copy_with generated: value
      end

      if value = ann.enum_type
        mapping = mapping.copy_with enum_type: value
      end

      mapping
    end
  end
end
