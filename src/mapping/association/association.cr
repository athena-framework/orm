# Base struct for all association mappings.
# Contains common properties shared by all association types.
abstract struct Athena::ORM::Mapping::Association
  def self.new(mapping : Driver::ColumnMapping) : self
    new(
      mapping.field_name,
      mapping.source_entity,
      mapping.target_entity,
      mapping.fetch_mode,
      mapping.id,
      mapping.orphan_removal,
      mapping.unique,
    )
  end

  # The name of the field in the entity that holds this association.
  getter field_name : String

  # The fully-qualified class name of the entity that contains this association.
  getter source_entity : AORM::Entity.class

  # The fully-qualified class name of the target entity.
  getter target_entity : AORM::Entity.class

  # The fetch strategy for loading the association.
  getter fetch_mode : FetchMode?

  # Whether this association is part of the identifier.
  getter? id : Bool?

  # Whether to remove orphaned entities when they are removed from the collection.
  getter? orphan_removal : Bool

  # Whether the association should be unique.
  getter? unique : Bool?

  def initialize(
    @field_name : String,
    @source_entity : AORM::Entity.class,
    @target_entity : AORM::Entity.class,
    @fetch_mode : FetchMode? = nil,
    @id : Bool? = nil,
    @orphan_removal : Bool? = false,
    @unique : Bool? = nil,
  )
  end
end
