module Athena::ORM::Mapping
  enum GeneratorType
    None
    Auto
    Sequence
    Table
    Identity
    Custom
  end

  struct ValueGeneratorMetadata
    getter type : AORM::Mapping::GeneratorType
    getter generator : AORM::Sequencing::Generators::Interface

    def self.from_annotations(
      column_name : String,
      generated_value : AORM::Mapping::Annotations::GeneratedValue?,
      sequence_generator : AORM::Mapping::Annotations::SequenceGenerator?
    )
      return nil unless generated_value

      generator_type : AORM::Mapping::GeneratorType = generated_value.strategy

      # TODO: Figure out how to get the target platform in here
      generator_type = generator_type.auto? ? AORM::Mapping::GeneratorType::Sequence : raise "TODO: Use the platform to determine this"

      generator_type, generator = case generator_type
                                  when .sequence?
                                    sequence_name = sequence_generator.try &.name
                                    allocation_size = sequence_generator.try(&.allocation_size) || 1_i64

                                    if sequence_name.nil?
                                      sequence_name = "users_#{column_name}_seq"
                                    end

                                    {generator_type, AORM::Sequencing::Generators::Sequence.new(sequence_name, allocation_size)}
                                  else
                                    return nil
                                  end

      new generator_type, generator
    end

    def initialize(@type : AORM::Mapping::GeneratorType, @generator : AORM::Sequencing::Generators::Interface); end
  end
end
