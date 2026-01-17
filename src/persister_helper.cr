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

    private def self.convert_individual_value(value : _, em : AORM::EntityManagerInterface)
      if value.is_a?(String | Number::Primitive | Bool)
        return [value]
      end

      if value.is_a? Enum
        return [value.value]
      end

      if value.is_a? AORM::Entity
        return [value]
      end

      # TODO: Handle composite identifiers

      # TODO: What to do here?
      [nil]
    end
  end
end
