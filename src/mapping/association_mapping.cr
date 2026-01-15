record Athena::ORM::Mapping::AssociationMapping,
  field_name : String,
  source_entity : AORM::Entity.class,
  target_entity : AORM::Entity.class do
  def self.from_column_mapping(mapping : Driver::ColumnMapping) : Athena::ORM::Mapping::FieldMapping
    new(
      mapping.field_name,
      mapping.source_entity.not_nil!,
      mapping.target_entity.not_nil!,
    )
  end
end
