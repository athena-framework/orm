record Athena::ORM::Mapping::FieldMapping,
  field_name : String,
  column_name : String,
  type : String,
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
  quoted : Bool? = nil do
  def self.from_column_mapping(mapping : Driver::ColumnMapping) : Athena::ORM::Mapping::FieldMapping
    Athena::ORM::Mapping::FieldMapping.new(
      mapping.field_name,
      mapping.column_name.not_nil!,
      mapping.type.not_nil!,
      id: mapping.id
    )
  end
end
