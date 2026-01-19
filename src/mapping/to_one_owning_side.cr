require "./owning_side"

abstract class Athena::ORM::Mapping::ToOneOwningSide < Athena::ORM::Mapping::OwningSide
  include Athena::ORM::Mapping::ToOne

  def self.new(
    mapping : Driver::ColumnMapping,
    naming_strategy : NamingStrategyInterface,
    entity_class : AORM::Entity.class,
    table : Class::TableInfo?,
    is_inheritance_type_single_table : Bool,
  ) : self
    # TODO: Handle mapping.join_columns

    instance = new mapping

    raise "not owning" unless instance.is_a? Mapping::ToOneOwningSide

    if instance.join_columns.empty?
      instance.join_columns.replace([
        JoinColumn.new(
          name: naming_strategy.join_column_name(instance.field_name, entity_class),
          referenced_column_name: naming_strategy.reference_column_name
        ),
      ])
    end

    unique_constraint_columns = [] of String

    instance.join_columns.each do |jc|
      if instance.id?
        raise "cannot set nullable field for join columns in a to-one association" unless jc.nullable.nil?

        jc.nullable = true
      else
        jc.nullable = true
      end

      if instance.is_a?(Mapping::OneToOne) && !is_inheritance_type_single_table
        if instance.join_columns.size == 1
          if mapping.id.nil?
            jc.unique = true
          end
        end
      else
        unique_constraint_columns << jc.name
      end

      if !jc.referenced_column_name
        jc.referenced_column_name = naming_strategy.reference_column_name
      end

      if jc.name.starts_with?('`')
        jc.name = jc.name.strip '`'
        jc.quoted = true
      end

      if jc.referenced_column_name.starts_with?('`')
        jc.referenced_column_name = jc.referenced_column_name.strip '`'
        jc.quoted = true
      end

      instance.source_to_target_key_columns[jc.name] = jc.referenced_column_name
      instance.join_column_field_names[jc.name] = jc.field_name || jc.name
    end

    unless unique_constraint_columns.empty?
      raise "table must be set before defining a one to one relationship" if table.nil?

      # TODO: Handle unique constraints
    end

    instance.target_to_source_key_columns = instance.source_to_target_key_columns.invert

    instance
  end

  def self.new(mapping : Driver::ColumnMapping) : self
    # TODO: Handle mapping.join_columns

    instance = new(
      mapping.field_name,
      mapping.source_entity.not_nil!,
      mapping.target_entity.not_nil!,
      mapping.inversed_by,
      mapping.fetch_mode,
      mapping.id,
      mapping.orphan_removal,
      mapping.unique,
      mapping.cascade,
    )

    # TODO: Handle mapping.join_columns

    if instance.orphan_removal?
      unless instance.cascade_remove?
        instance.cascade << "remove"
      end

      instance.unique = nil
    end

    instance
  end

  property source_to_target_key_columns : Hash(String, String) = {} of String => String
  property target_to_source_key_columns : Hash(String, String) = {} of String => String

  property join_columns : Array(JoinColumn) = [] of JoinColumn
  property join_column_field_names : Hash(String, String) = {} of String => String

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
end
