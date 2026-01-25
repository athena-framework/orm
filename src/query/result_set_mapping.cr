module Athena::ORM::Query
  class ResultSetMapping
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

    # TODO: newObjects?
    # TODO: NestedNewObjectArgs?
    # TODO: metadataParameterMapping?
    # TODO: discriminatorMapping?
    # TODO: nestedEntities?

    # Adds a root entity result to the mapping.
    def add_root_entity(
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

      self
    end
  end
end
