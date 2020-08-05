struct Athena::ORM::Mapping::JoinColumnMetadata < Athena::ORM::Mapping::ColumnMetadata
  protected def self.build_metadata(
    context : ClassFactory::Context,
    class_metadata : ClassBase,
    target_entity : AORM::Entity.class,
    property_name : String
  ) : self
    # TODO: Have a better way to resolve column names
    reference_column_name = "id"

    target_entity_metadata = context.metadata_factory.metadata target_entity
    referenced_column = target_entity_metadata.column reference_column_name

    new(
      "#{property_name}_id",
      false,
      referenced_column.not_nil!.type, # TODO: Maybe resolve this lazily?
      class_metadata.table_name,
      false, # TODO: Base this off JoinColumn annotation
      reference_column_name,
      nil
    )
  end

  getter reference_column_name : String?
  getter aliased_name : String?

  def initialize(
    column_name : String,
    is_primary_key : Bool,
    type : AORM::Types::Type,
    table_name : String?,
    nilable : Bool,
    @reference_column_name : String?,
    @aliased_name : String?
  )
    super column_name, is_primary_key, type, table_name, nilable
  end
end
