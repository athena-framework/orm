class Athena::ORM::Mapping::ClassFactory < Athena::ORM::Mapping::AbstractClassFactory
  protected property! entity_manager : AORM::EntityManagerInterface?

  private getter target_platform : AORM::Platforms::Platform do
    self.entity_manager.connection.database_platform
  end

  def initialize
    @driver = Driver::Annotation.new
  end

  private def load(metadata : ClassInterface, parent_metadata : ClassInterface?, root_entity_found : Bool, non_superclass_parents : Array(String)) : Nil
    # TODO: Handle parent

    @driver.load_metadata_for_entity metadata

    if parent_metadata && root_entity_found
      # TODO: Inherit ID generator
    else
      self.complete_id_generator_mapping metadata
    end

    # TODO: handle `is_mapped_superclass`

    # TODO: Handle parent

    # TODO: Something about default discriminator map?

    # TODO: Eventing

    # TODO: Find abstract types not in discriminator map

    self.validate_runtime_metadata metadata, parent_metadata
  end

  private def validate_runtime_metadata(metadata : ClassInterface, parent_metadata : ClassInterface?) : Nil
    # TODO: Validate stuff
  end

  private def complete_id_generator_mapping(metadata : ClassInterface) : Nil
    id_generator_type = metadata.id_generator_type

    if id_generator_type.auto?
      metadata.id_generator_type = self.determine_id_generator_strategy self.target_platform
    end

    case metadata.id_generator_type
    when .identity?
      sequence_name = nil
      field_name = !metadata.identifier.empty? ? metadata.single_identifier_field_name : nil
      platform = self.target_platform

      generator = field_name && metadata.field_mappings[field_name].type == "bigint" ? AORM::ID::BigIntegerIdentityGenerator.new : AORM::ID::IdentityGenerator.new

      metadata.id_generator = generator
    when .none?
      metadata.id_generator = AORM::ID::AssignedGenerator.new
    else
      # TODO: Handle other types (SEQUENCE, CUSTOM)
    end
  end

  private def determine_id_generator_strategy(platform : AORM::Platforms::Platform) : GeneratedValueStrategy
    em = self.entity_manager

    # TODO: Something about id generation preferences on the EM configuration?

    # TODO: Handle non-identity strategies

    GeneratedValueStrategy::IDENTITY
  end

  private def new_class_metadata_instance(entity_class : T.class) : ClassInterface forall T
    Class(T).new entity_class
  end
end
