module Athena::ORM::Mapping
  enum GeneratorType
    None
    Auto
    Sequence
    Table
    Identity
    Custom
  end

  record ValueGeneratorMetadata,
    type : AORM::Mapping::GeneratorType,
    generator : AORM::Sequencing::Generators::Interface
end
