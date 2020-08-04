require "./column"
require "./table"

module Athena::ORM::Mapping
  abstract struct ColumnBase
    include Athena::ORM::Mapping::Property
  end

  struct Column(IvarType, EntityType) < Athena::ORM::Mapping::ColumnBase
    include Athena::ORM::Mapping::Common(EntityType)

    protected def self.build_metadata(
      context : ClassFactory::Context,
      name : String,
      class_metadata : ClassBase,
      column : Annotations::Column,
      id : Annotations::ID? = nil,
      generated_value : Annotations::GeneratedValue? = nil,
      sequence_generator : Annotations::SequenceGenerator? = nil
    ) : self
      is_primary_key = false
      value_generator = nil

      type = AORM::Types::Type.get_type(column.type_class || IvarType)

      if id
        is_primary_key = true

        if type.can_require_sql_conversion?
          # TODO: Use proper exception type
          raise "SQL Conversion not allowed for PK"
        end

        value_generator = generated_value.nil? ? nil : AORM::Mapping::ValueGeneratorMetadata.build_metadata(context, class_metadata, name, type, generated_value, sequence_generator)
      end

      new(
        name,
        is_primary_key,
        type,
        column.name || name,
        class_metadata.table_name,
        column.nilable,
        value_generator
      )
    end

    getter type : AORM::Types::Type

    getter column_name : String
    getter value_generator : AORM::Mapping::ValueGeneratorMetadata?
    getter entity_class : EntityType.class
    getter table_name : String?

    getter? nilable : Bool

    def initialize(
      name : String,
      is_primary_key : Bool,
      @type : AORM::Types::Type,
      @column_name : String,
      @table_name : String?,
      @nilable : Bool,
      @value_generator : ValueGeneratorMetadata?,
      @entity_class : EntityType.class = EntityType
    )
      super name, is_primary_key
    end

    def has_value_generator? : Bool
      !@value_generator.nil?
    end

    def value_generation_executor(platform : AORM::Platforms::Platform) : AORM::Sequencing::Executors::Interface?
      if generator = @value_generator
        AORM::Sequencing::Executors::ColumnValueGeneration.new self, generator.generator
      end
    end
  end
end
