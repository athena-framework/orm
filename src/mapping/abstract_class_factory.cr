require "./class_factory_interface"

abstract class Athena::ORM::Mapping::AbstractClassFactory
  include Athena::ORM::Mapping::ClassFactoryInterface

  @loaded_metadata = Hash(AORM::Entity.class, ClassInterface).new

  def metadata(for entity_class : AORM::Entity.class) : ClassInterface
    if metadata = @loaded_metadata[entity_class]?
      return metadata
    end

    self.load entity_class

    @loaded_metadata[entity_class]
  end

  private abstract def new_class_metadata_instance(entity_class : AORM::Entity.class) : ClassInterface
  private abstract def load(metadata : ClassInterface, parent : ClassInterface?, root_entity_found : Bool, non_superclass_parents : Array(String)) : Nil

  private def load(entity_class : AORM::Entity.class) : Nil
    # TODO: Handle loading parent types

    metadata = self.new_class_metadata_instance entity_class

    self.load metadata, nil, false, [] of String

    @loaded_metadata[entity_class] = metadata

    metadata
  end
end
