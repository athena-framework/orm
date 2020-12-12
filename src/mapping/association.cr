require "./property"

module Athena::ORM::Mapping
  enum FetchMode
    Lazy
    Eager
  end

  # TODO: Make this an abstract struct again
  module AssociationMetadata(SourceEntity, TargetEntity)
    include Athena::ORM::Mapping::Property

    getter name : String

    getter fetch_mode : FetchMode
    getter source_entity : AORM::Entity.class
    getter target_entity : AORM::Entity.class
    getter mapped_by : String?
    getter inversed_by : String?

    getter? is_owning_side : Bool
    getter? is_orphan_removal : Bool = false
    getter? is_primary_key : Bool

    def initialize(
      @name : String,
      @is_primary_key : Bool,
      @fetch_mode : FetchMode,
      @mapped_by : String?,
      @inversed_by : String?,
      @is_owning_side : Bool,
      @is_orphan_removal : Bool,
      @source_entity : AORM::Entity.class = SourceEntity,
      @target_entity : AORM::Entity.class = TargetEntity
    )
    end

    def value_generation_executor(platform : AORM::Platforms::Platform) : AORM::Sequencing::Executors::Interface?
      # TODO: Handle association value generation executors
      nil
    end

    def set_value(entity : AORM::Entity, value : _) : Nil
      raise "BUG: Invoked default set_value"
    end

    def get_value(entity : AORM::Entity)
      raise "BUG: Invoked default get_value"
    end
  end

  abstract struct ToOneAssociationMetadata(SourceEntity, TargetEntity)
    include AssociationMetadata(SourceEntity, TargetEntity)

    protected def self.build_metadata(
      context : ClassFactory::Context,
      name : String,
      class_metadata : ClassBase,
      one_to_one : Annotations::OneToOne,
      id : Annotations::ID? = nil
    ) : self
      is_primary_key = false
      is_owning_side = one_to_one.mapped_by.nil?

      if id
        is_primary_key = true

        # TODO: Make this a compile time error
        raise "No orphan_removal on PKs" if one_to_one.orphan_removal

        class_metadata.identifier.add? name
      end

      # TODO: Handle JoinColumn and JoinColumns annotations
      join_columns = !is_owning_side ? Array(JoinColumnMetadata).new : [JoinColumnMetadata.build_metadata(context, class_metadata, TargetEntity, name)]

      # TODO: Set type of join_column

      # TODO: Handle unique constraints

      new(
        name,
        is_primary_key,
        one_to_one.fetch_mode,
        one_to_one.mapped_by,
        one_to_one.inversed_by,
        is_owning_side,
        one_to_one.orphan_removal, # TODO: orphan_removal implies cascade remove
        join_columns
      )
    end

    getter join_columns : Array(JoinColumnMetadata)

    def initialize(
      name : String,
      is_primary_key : Bool,
      fetch_mode : FetchMode,
      mapped_by : String?,
      inversed_by : String?,
      is_owning_side : Bool,
      is_orphan_removal : Bool,
      @join_columns : Array(JoinColumnMetadata)
    )
      super name, is_primary_key, fetch_mode, mapped_by, inversed_by, is_owning_side, is_orphan_removal
    end

    def set_value(entity : SourceEntity, value : _) : Nil
      {% begin %}
        case @name
          {% for column in SourceEntity.instance_vars %}
            when {{column.name.stringify}}
              if value.is_a? {{column.type}}
                pointerof(entity.@{{column.id}}).value = value
              end
          {% end %}
        end
      {% end %}
    end

    def get_value(entity : SourceEntity) : AORM::Mapping::Value
      {% begin %}
        case @name
          {% for column in SourceEntity.instance_vars %}
            when {{column.name.stringify}} then AORM::Mapping::ColumnValue.new {{column.name.stringify}}, entity.@{{column.id}}
          {% end %}
        else
          raise "BUG: Unknown column #{@name} within #{SourceEntity}"
        end
      {% end %}
    end
  end

  struct OneToOneAssociationMetadata(SourceEntity, TargetEntity) < ToOneAssociationMetadata(SourceEntity, TargetEntity); end
end
