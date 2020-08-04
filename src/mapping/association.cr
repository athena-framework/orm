module Athena::ORM::Mapping
  enum FetchMode
    Lazy
    Eager
  end

  struct Association(SourceEntity, TargetEntity)
    include Athena::ORM::Mapping::Property
    include Athena::ORM::Mapping::Common(SourceEntity)

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
      join_columns = !is_owning_side ? Array(JoinColumn).new : [JoinColumn.build_metadata(context, name)]

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

    getter fetch_mode : FetchMode
    getter source_entity : AORM::Entity.class
    getter target_entity : AORM::Entity.class
    getter mapped_by : String?
    getter inversed_by : String?
    getter join_columns : Array(JoinColumn)

    getter? is_owning_side : Bool
    getter? is_orphan_removal : Bool = false

    def initialize(
      name : String,
      is_primary_key : Bool,
      @fetch_mode : FetchMode,
      @mapped_by : String?,
      @inversed_by : String?,
      @is_owning_side : Bool,
      @is_orphan_removal : Bool,
      @join_columns : Array(JoinColumn),
      @source_entity : AORM::Entity.class = SourceEntity,
      @target_entity : AORM::Entity.class = TargetEntity
    )
      super name, is_primary_key
    end

    def value_generation_executor(platform : AORM::Platforms::Platform) : AORM::Sequencing::Executors::Interface?
      # TODO: Handle association value generators
    end
  end
end
