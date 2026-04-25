# Base class for the side of a bidirectional association whose mapping points
# at the owning side via `mapped_by`. The owning side is where the foreign key
# (or join-table reference) lives; the inverse side is read-only with respect
# to the relationship.
abstract class Athena::ORM::Mapping::InverseSide < Athena::ORM::Mapping::Association
  def self.new(mapping : Driver::ColumnMapping) : self
    new(
      mapping.field_name,
      mapping.source_entity.not_nil!,
      mapping.target_entity.not_nil!,
      mapping.mapped_by.not_nil!,
      mapping.fetch_mode,
      mapping.id,
      mapping.orphan_removal,
      mapping.unique,
      mapping.cascade,
    )
  end

  # The name of the field on the owning side that completes the bidirectional association.
  property mapped_by : String

  def initialize(
    field_name : String,
    source_entity : AORM::Entity.class,
    target_entity : AORM::Entity.class,
    @mapped_by : String,
    fetch_mode : FetchMode? = nil,
    id : Bool? = nil,
    orphan_removal : Bool? = false,
    unique : Bool? = nil,
    cascade : Array(String)? = nil,
  )
    super field_name, source_entity, target_entity, fetch_mode, id, orphan_removal || false, unique, cascade
  end
end
