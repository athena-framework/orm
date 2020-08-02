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

    protected def self.build_metadata(
      context : ClassFactory::Context,
      class_metadata : ClassBase,
      column_name : String,
      column_type : AORM::Types::Type,
      generated_value : Annotations::GeneratedValue?,
      sequence_generator : Annotations::SequenceGenerator?
    ) : self?
      return nil unless generated_value

      platform = context.target_platform
      generator_type : GeneratorType = generated_value.strategy

      if generator_type.auto? || generator_type.identity?
        generator_type = (platform.prefers_sequences? || platform.uses_sequence_emulated_identity_columns?) ? GeneratorType::Sequence : (platform.prefers_identity_columns? ? GeneratorType::Identity : GeneratorType::Table)
      end

      generator_type, generator = case generator_type
                                  in .sequence?
                                    sequence_name = sequence_generator.try &.name
                                    allocation_size = sequence_generator.try(&.allocation_size) || 1_i64

                                    if sequence_name.nil?
                                      sequence_name = platform.fix_schema_element_name(
                                        "#{platform.sequence_prefix class_metadata.table_name, class_metadata.schema_name}_#{column_name}_seq"
                                      )
                                    end

                                    {generator_type, AORM::Sequencing::Generators::Sequence.new(sequence_name, allocation_size)}
                                  in .identity?, .table?, .custom? then return nil # TODO: Suppor other types of generators
                                  in .none?, .auto? then return nil                # Auto is a pseudo type and will be resolved to something else
                                  end

      new generator_type, generator
    end

    def initialize(@type : AORM::Mapping::GeneratorType, @generator : AORM::Sequencing::Generators::Interface); end
  end
end
