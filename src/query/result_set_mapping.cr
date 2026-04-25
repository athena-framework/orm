module Athena::ORM::Query
  class ResultSetMapping
    # Discriminates how a result column is hydrated. Tracked alongside the
    # `columns` insertion-order list so the hydrator can dispatch per column
    # without re-deriving the column kind from the various per-kind mappings.
    enum ColumnKind
      Field
      Scalar
      Meta
    end

    # An ordered entry in the result set's column list. Insertion order matches
    # the SELECT's column order, which in turn matches the cursor read order
    # (`DB::ResultSet` advances column-by-column), so iterating `columns`
    # corresponds 1:1 with the cursor's per-row reads.
    record Column, column_name : String, kind : ColumnKind

    # Whether result mixes scalars with entities
    getter? mixed : Bool = false
    getter? select : Bool = true

    # Maps alias names to entity class
    getter alias_map : Hash(String, AORM::Entity.class) = {} of String => AORM::Entity.class

    # Maps alias names to related association field names
    getter relation_map : Hash(String, String) = {} of String => String

    # Maps alias names to parent alias names
    getter parent_alias_map : Hash(String, String) = {} of String => String

    # Maps column names in result set to field names for each class
    getter field_mappings : Hash(String, String) = {} of String => String

    # Map field names for each class to alias
    getter column_alias_mappings : Hash(AORM::Entity.class, Hash(String, Hash(String, String))) = Hash(AORM::Entity.class, Hash(String, Hash(String, String))).new.compare_by_identity

    # Maps column names in the result set to the alias/field name to use in the mapped result
    getter scalar_mappings : Hash(String, String | Int32) = {} of String => String | Int32

    # TODO: Handle enum mappings

    # Type mappings: column name => type name
    getter type_mappings : Hash(String, String) = {} of String => String

    # Maps entities in the result set to the alias name to use in the mapped result.
    getter entity_mappings : Hash(String, String?) = {} of String => String?

    # Meta mappings: column name => field name (FKs, discriminators)
    getter meta_mappings : Hash(String, String) = {} of String => String

    # Maps column names to the alias they belong to
    getter column_owner_map : Hash(String, String) = {} of String => String

    # TODO: Handle discriminator map

    # Index by: alias => column name
    getter index_by_map : Hash(String, String) = {} of String => String

    # Maps column names to class that declares the field
    getter declaring_classes : Hash(String, AORM::Entity.class) = {} of String => AORM::Entity.class

    # Identifier columns per alias: alias => column_name => true
    getter is_identifier_column : Hash(String, Hash(String, Bool)) = {} of String => Hash(String, Bool)

    # Result columns in SELECT/insertion order, each tagged with its kind.
    getter columns : Array(Column) = [] of Column

    # TODO: newObjects?
    # TODO: NestedNewObjectArgs?
    # TODO: metadataParameterMapping?
    # TODO: discriminatorMapping?
    # TODO: nestedEntities?

    # Adds a root entity result to the mapping. When *result_alias* is given,
    # the result is treated as mixed (the entity is keyed under *result_alias*
    # alongside any scalar columns).
    def add_entity_result(
      entity_class : AORM::Entity.class,
      alias_name : String,
      result_alias : String? = nil,
    ) : self
      @alias_map[alias_name] = entity_class
      @entity_mappings[alias_name] = result_alias

      if result_alias
        @mixed = true
      end

      self
    end

    # Adds a child entity that is hydrated from the same row as a parent entity
    # (a fetch-joined association).
    def add_joined_entity_result(
      entity_class : AORM::Entity.class,
      alias_name : String,
      parent_alias : String,
      relation : String,
    ) : self
      @alias_map[alias_name] = entity_class
      @parent_alias_map[alias_name] = parent_alias
      @relation_map[alias_name] = relation
      self
    end

    # TODO: setDiscriminatorColumn

    def add_field_result(
      alias_name : String,
      column_name : String,
      field_name : String,
      declaring_class : AORM::Entity.class | Nil = nil,
    ) : self
      @field_mappings[column_name] = field_name
      @column_owner_map[column_name] = alias_name

      declaring_class = declaring_class || @alias_map[alias_name]
      @declaring_classes[column_name] = declaring_class

      unless @column_alias_mappings.has_key? declaring_class
        @column_alias_mappings[declaring_class] = Hash(String, Hash(String, String)).new do |hash2, key2|
          hash2[key2] = Hash(String, String).new
        end
      end

      @column_alias_mappings[declaring_class][alias_name][field_name] = column_name

      if !@mixed && !@scalar_mappings.empty?
        @mixed = true
      end

      @columns << Column.new(column_name, ColumnKind::Field)

      self
    end

    # Adds a scalar (non-entity) result column — typically an aggregate
    # (`COUNT(*)`, `SUM(x)`) or a column unmapped to any entity field.
    def add_scalar_result(
      column_name : String,
      result_alias : String | Int32,
      type : String = "string",
    ) : self
      @scalar_mappings[column_name] = result_alias
      @type_mappings[column_name] = type

      if !@mixed && !@field_mappings.empty?
        @mixed = true
      end

      @columns << Column.new(column_name, ColumnKind::Scalar)

      self
    end

    # Adds a meta-column (foreign key, discriminator, etc.) — present in the
    # result set but not exposed as a regular entity field.
    def add_meta_result(
      alias_name : String,
      column_name : String,
      field_name : String,
      is_identifier : Bool = false,
      type : String? = nil,
    ) : self
      @meta_mappings[column_name] = field_name
      @column_owner_map[column_name] = alias_name

      if is_identifier
        @is_identifier_column[alias_name] ||= {} of String => Bool
        @is_identifier_column[alias_name][column_name] = true
      end

      if type
        @type_mappings[column_name] = type
      end

      @columns << Column.new(column_name, ColumnKind::Meta)

      self
    end

    # Configures collection indexing by entity field. Resolves *field_name* to
    # its result column via `@field_mappings`.
    def add_index_by(alias_name : String, field_name : String) : self
      @field_mappings.each do |column, field|
        if field == field_name && @column_owner_map[column]? == alias_name
          @index_by_map[alias_name] = column
          return self
        end
      end

      raise "Cannot add index-by: field '#{field_name}' is not registered on alias '#{alias_name}'"
    end

    # Configures collection indexing by the given result column directly.
    def add_index_by_column(alias_name : String, column_name : String) : self
      @index_by_map[alias_name] = column_name
      self
    end

    # Whether *alias_name* has an index-by configured.
    def has_index_by?(alias_name : String) : Bool
      @index_by_map.has_key? alias_name
    end

    # Whether *column_name* is registered as a regular entity-field column.
    def field_result?(column_name : String) : Bool
      @field_mappings.has_key? column_name
    end

    # Whether *column_name* is registered as a scalar result column.
    def scalar_result?(column_name : String) : Bool
      @scalar_mappings.has_key? column_name
    end

    # Whether *alias_name* has a parent alias (i.e., is a joined child).
    def has_parent_alias?(alias_name : String) : Bool
      @parent_alias_map.has_key? alias_name
    end

    # Total number of entity results (root + joined).
    def entity_result_count : Int32
      @alias_map.size
    end

    # The first registered alias — typically the root entity. Returns nil if
    # nothing has been added yet.
    def root_alias : String?
      @alias_map.first_key?
    end

    # Aliases that have a parent (i.e., joined-entity aliases).
    def joined_aliases : Array(String)
      @parent_alias_map.keys
    end

    # The entity class registered under *alias_name*. Raises if *alias_name*
    # has not been added.
    def class_metadata(alias_name : String) : AORM::Entity.class
      @alias_map[alias_name]
    end

    # The entity field name backing *column_name*. Raises if not a field
    # result.
    def field_name(column_name : String) : String
      @field_mappings[column_name]
    end

    # The owning alias for *column_name*. Raises if no owner is recorded.
    def entity_alias(column_name : String) : String
      @column_owner_map[column_name]
    end

    # Whether a column alias has been registered for *(alias_name, field_name)*.
    # Used by the persister to avoid generating duplicate column aliases for a
    # field that has already been mapped to one.
    def has_column_alias_by_field?(alias_name : String, field_name : String) : Bool
      return false unless @alias_map.has_key? alias_name

      declaring_class = @alias_map[alias_name]
      mapping = @column_alias_mappings[declaring_class]?
      mapping.try(&.[alias_name]?).try(&.has_key?(field_name)) || false
    end

    # The column alias previously registered for *(alias_name, field_name)*.
    # Use `has_column_alias_by_field?` first to verify presence; this raises
    # on missing entries.
    def column_alias_by_field(alias_name : String, field_name : String) : String
      declaring_class = @alias_map[alias_name]
      @column_alias_mappings[declaring_class][alias_name][field_name]
    end
  end
end
