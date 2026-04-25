require "./inverse_side"
require "./one_to_many"

# Mapping for the inverse side of a OneToMany association.
# OneToMany is always the inverse side; the corresponding ManyToOne owns the FK.
class Athena::ORM::Mapping::OneToManyInverseSide < Athena::ORM::Mapping::InverseSide
  include Athena::ORM::Mapping::OneToMany

  def self.new(mapping : Driver::ColumnMapping) : self
    raise "OneToMany requires `mapped_by`" unless mapping.mapped_by

    instance = new(
      mapping.field_name,
      mapping.source_entity.not_nil!,
      mapping.target_entity.not_nil!,
      mapping.mapped_by.not_nil!,
      mapping.fetch_mode,
      nil,
      mapping.orphan_removal,
      nil,
      mapping.cascade,
    )

    instance.index_by = mapping.index_by

    if instance.orphan_removal? && !instance.cascade_remove?
      instance.cascade << "remove"
    end

    instance
  end

  property index_by : String?

  def initialize(
    field_name : String,
    source_entity : AORM::Entity.class,
    target_entity : AORM::Entity.class,
    mapped_by : String,
    fetch_mode : FetchMode? = nil,
    id : Bool? = nil,
    orphan_removal : Bool? = false,
    unique : Bool? = nil,
    cascade : Array(String)? = nil,
  )
    super field_name, source_entity, target_entity, mapped_by, fetch_mode, id, orphan_removal || false, unique, cascade
  end

  def one_to_many? : Bool
    true
  end

  def to_many? : Bool
    true
  end
end
