class Athena::ORM::Mapping::ClassFactory < Athena::ORM::Mapping::AbstractClassFactory
  protected setter entity_manager : AORM::EntityManagerInterface?

  def initialize
    @driver = Driver::Annotation.new
  end

  private def load(metadata : ClassInterface, parent : ClassInterface?, root_entity_found : Bool, non_superclass_parents : Array(String)) : Nil
    # TODO: Handle if there is a parent
    @driver.load_metadata_for_entity metadata
  end

  private def new_class_metadata_instance(entity_class : T.class) : ClassInterface forall T
    Class(T).new entity_class
  end
end
