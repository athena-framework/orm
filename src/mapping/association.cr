# Base class for all association mappings.
# Contains common properties shared by all association types.
abstract class Athena::ORM::Mapping::Association
  def self.new(mapping : Driver::ColumnMapping) : self
    new(
      mapping.field_name,
      mapping.source_entity,
      mapping.target_entity,
      mapping.fetch_mode,
      mapping.id,
      mapping.orphan_removal,
      mapping.unique,
      mapping.cascade,
    )
  end

  # The name of the field in the entity that holds this association.
  property field_name : String

  # The fully-qualified class name of the entity that contains this association.
  property source_entity : AORM::Entity.class

  # The fully-qualified class name of the target entity.
  property target_entity : AORM::Entity.class

  # The fetch strategy for loading the association.
  property fetch_mode : FetchMode?

  # Whether this association is part of the identifier.
  property? id : Bool?

  # Whether to remove orphaned entities when they are removed from the collection.
  property? orphan_removal : Bool

  # Whether the association should be unique.
  property? unique : Bool?

  getter cascade : Array(String)

  def initialize(
    @field_name : String,
    @source_entity : AORM::Entity.class,
    @target_entity : AORM::Entity.class,
    @fetch_mode : FetchMode? = nil,
    @id : Bool? = nil,
    @orphan_removal : Bool? = false,
    @unique : Bool? = nil,
    cascade : Array(String)? = nil,
  )
    @cascade = cascade || [] of String
  end

  def cascade_persist? : Bool
    @cascade.includes? "persist"
  end

  def cascade_remove? : Bool
    @cascade.includes? "remove"
  end

  def cascade_detach? : Bool
    @cascade.includes? "detach"
  end

  # TODO: Make this an enum
  def type : String
    # ManyToOne is also ToOne (and a kind of OneToOne in our hierarchy via ToOneOwningSide), so check the more specific markers first.
    return "many_to_one" if self.is_a? ManyToOne
    return "one_to_many" if self.is_a? OneToMany
    return "many_to_many" if self.is_a? ManyToMany
    return "one_to_one" if self.is_a? OneToOne

    raise "Cannot determine type for #{self.class}"
  end
end
