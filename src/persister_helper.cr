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
