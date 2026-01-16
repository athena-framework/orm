class Athena::ORM::Mapping::Association::JoinColumn
  property name : String
  property referenced_column_name : String
  property deferrable : Bool?
  property unique : Bool?
  property quoted : Bool?
  property field_name : String?
  property on_delete : String?
  property column_definition : String?
  property nullable : Bool?

  def initialize(
    @name : String,
    @referenced_column_name : String,
    @deferrable : Bool? = nil,
    @unique : Bool? = nil,
    @quoted : Bool? = nil,
    @field_name : String? = nil,
    @on_delete : String? = nil,
    @column_definition : String? = nil,
    @nullable : Bool? = nil
  )
  end
end
