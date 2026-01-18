module Athena::ORM
  enum ParameterType
    NULL
    INTEGER
    STRING
    LARGE_OBJECT
    BOOLEAN
    BINARY
    ASCII
  end

  enum ArrayParameterType
    INTEGER
    STRING
    BINARY
    ASCII
  end

  module PersisterHelper
    # Returns the types for a given field, handling both regular fields and associations.
    # For associations, returns the types of the join column(s).
    def self.type_of_field(field_name : String, metadata : Mapping::ClassInterface, em : AORM::EntityManagerInterface) : Array(String)
      if fm = metadata.field_mappings[field_name]?
        return [fm.type]
      end

      return [] of String unless assoc = metadata.association_mappings[field_name]?

      unless assoc.owning_side?
        if assoc.is_a?(Mapping::InverseSide)
          return self.type_of_field(assoc.mapped_by, em.class_metadata(assoc.target_entity), em)
        end

        return [] of String
      end

      # TODO: Handle many-to-many owning side (join_table)

      types = [] of String
      target_class = em.class_metadata(assoc.target_entity)

      if assoc.is_a?(Mapping::ToOneOwningSide)
        assoc.join_columns.each do |join_column|
          types << self.type_of_column(join_column.referenced_column_name, target_class, em)
        end
      end

      types
    end

    # Returns the type for a given column name by looking up field mappings
    # and recursively resolving association join columns.
    def self.type_of_column(column_name : String, metadata : Mapping::ClassInterface, em : AORM::EntityManagerInterface) : String
      if field_name = metadata.field_names[column_name]?
        if fm = metadata.field_mappings[field_name]?
          return fm.type
        end
      end

      # Iterate over to-one owning side association mappings
      metadata.association_mappings.each_value do |assoc|
        next unless assoc.to_one_owning_side?
        next unless assoc.is_a?(Mapping::ToOneOwningSide)

        assoc.join_columns.each do |join_column|
          if join_column.name == column_name
            target_column_name = join_column.referenced_column_name
            target_class = em.class_metadata(assoc.target_entity)

            return self.type_of_column(target_column_name, target_class, em)
          end
        end
      end

      # TODO: Iterate over many-to-many owning side association mappings

      raise "Could not resolve type of column '#{column_name}' of class '#{metadata.entity_class}'"
    end

    def self.infer_parameter_types(field : String, value : _, metadata : Mapping::ClassInterface, em : AORM::EntityManagerInterface) : Array(ParameterType | ArrayParameterType | String)
      types = [] of ParameterType | ArrayParameterType | String

      if fm = metadata.field_mappings[field]?
        types << fm.type
      elsif am = metadata.association_mappings[field]?
        # TODO: Handle associations
      else
        types << ParameterType::STRING
      end

      # TODO: Handle array values

      types
    end

    def self.convert_to_parameter_value(value : _, em : AORM::EntityManagerInterface)
      # TODO: Handle array values

      self.convert_individual_value value, em
    end

    private def self.convert_individual_value(value : ::Enum, em : AORM::EntityManagerInterface)
      [value.value]
    end

    private def self.convert_individual_value(value : AORM::Entity, em : AORM::EntityManagerInterface) : Array(DB::Any)
      class_metadata = em.class_metadata value.class

      if class_metadata.is_identifier_composite
        # TODO: Handle composite PKs
      end

      [em.unit_of_work.single_identifier_value value] of DB::Any
    end

    private def self.convert_individual_value(value : DB::Any, em : AORM::EntityManagerInterface) : Array(DB::Any)
      [value] of DB::Any
    end
  end
end
