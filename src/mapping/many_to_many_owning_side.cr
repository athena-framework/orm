require "./owning_side"
require "./many_to_many"
require "./join_table"

# Mapping for the owning side of a ManyToMany association.
# The owning side is responsible for managing the join table.
class Athena::ORM::Mapping::ManyToManyOwningSide < Athena::ORM::Mapping::OwningSide
  include Athena::ORM::Mapping::ManyToMany

  def self.new(
    mapping : Driver::ColumnMapping,
    naming_strategy : NamingStrategyInterface,
    source_class : AORM::Entity.class,
    target_class : AORM::Entity.class,
  ) : self
    instance = new mapping

    # Build join table if not provided
    if instance.join_table.nil?
      join_table_name = naming_strategy.join_table_name(
        source_class.name.split("::").last,
        target_class.name.split("::").last,
        instance.field_name
      )
      instance.join_table = JoinTable.new(name: join_table_name)
    end

    join_table = instance.join_table.not_nil!

    # Build join columns if not provided
    if join_table.join_columns.empty?
      join_table.join_columns << JoinColumn.new(
        name: naming_strategy.join_key_column_name(source_class.name.split("::").last, nil),
        referenced_column_name: naming_strategy.reference_column_name
      )
    end

    # Build inverse join columns if not provided
    if join_table.inverse_join_columns.empty?
      join_table.inverse_join_columns << JoinColumn.new(
        name: naming_strategy.join_key_column_name(target_class.name.split("::").last, nil),
        referenced_column_name: naming_strategy.reference_column_name
      )
    end

    # Process join columns
    join_table.join_columns.each do |jc|
      jc.nullable = false

      if jc.name.starts_with?('`')
        jc.name = jc.name.strip('`')
        jc.quoted = true
      end

      if jc.referenced_column_name.starts_with?('`')
        jc.referenced_column_name = jc.referenced_column_name.strip('`')
        jc.quoted = true
      end

      instance.relation_to_source_key_columns[jc.name] = jc.referenced_column_name
      instance.join_column_field_names[jc.name] = jc.field_name || jc.name
    end

    # Process inverse join columns
    join_table.inverse_join_columns.each do |jc|
      jc.nullable = false

      if jc.name.starts_with?('`')
        jc.name = jc.name.strip('`')
        jc.quoted = true
      end

      if jc.referenced_column_name.starts_with?('`')
        jc.referenced_column_name = jc.referenced_column_name.strip('`')
        jc.quoted = true
      end

      instance.relation_to_target_key_columns[jc.name] = jc.referenced_column_name
    end

    instance
  end

  def self.new(mapping : Driver::ColumnMapping) : self
    instance = new(
      mapping.field_name,
      mapping.source_entity.not_nil!,
      mapping.target_entity.not_nil!,
      mapping.inversed_by,
      mapping.fetch_mode,
      nil, # id is always nil for to-many
      mapping.orphan_removal,
      nil, # unique is not applicable
      mapping.cascade,
    )

    instance.index_by = mapping.index_by

    # Apply custom join table settings from annotation if provided
    if jt = mapping.join_table
      if name = jt["name"]?
        instance.join_table = JoinTable.new(
          name: name,
          schema: jt["schema"]?
        )
      end
    end

    # Add custom join columns (source entity to join table)
    if join_col_defs = mapping.join_column_defs
      join_table = instance.join_table ||= JoinTable.new(name: "")
      join_col_defs.each do |jcd|
        join_table.join_columns << JoinColumn.new(
          name: jcd.name || "",
          referenced_column_name: jcd.referenced_column_name || "id"
        )
      end
    end

    # Add custom inverse join columns (join table to target entity)
    if inv_join_col_defs = mapping.inverse_join_column_defs
      join_table = instance.join_table ||= JoinTable.new(name: "")
      inv_join_col_defs.each do |jcd|
        join_table.inverse_join_columns << JoinColumn.new(
          name: jcd.name || "",
          referenced_column_name: jcd.referenced_column_name || "id"
        )
      end
    end

    instance
  end

  # Maps join table column name to source entity column name.
  property relation_to_source_key_columns : Hash(String, String) = {} of String => String

  # Maps join table column name to target entity column name.
  property relation_to_target_key_columns : Hash(String, String) = {} of String => String

  # The join table mapping.
  property join_table : JoinTable?

  # Maps join column names to field names.
  property join_column_field_names : Hash(String, String) = {} of String => String

  # Optional index column for indexed collections.
  property index_by : String?

  def initialize(
    field_name : String,
    source_entity : AORM::Entity.class,
    target_entity : AORM::Entity.class,
    inversed_by : String? = nil,
    fetch_mode : FetchMode? = nil,
    id : Bool? = nil,
    orphan_removal : Bool? = false,
    unique : Bool? = nil,
    cascade : Array(String)? = nil,
  )
    super field_name, source_entity, target_entity, inversed_by, fetch_mode, id, orphan_removal || false, unique, cascade
  end

  def many_to_many? : Bool
    true
  end

  def to_many? : Bool
    true
  end
end
