abstract class Athena::ORM::Entity
  include Athena::ORM::Storable

  macro inherited
    # :nodoc:
    #
    # Each entity subclass creates and loads its own typed metadata.
    # This preserves the specific type T for macro-based annotation processing.
    def self.create_class_metadata(driver : AORM::Mapping::Driver::Annotation) : AORM::Mapping::ClassInterface
      metadata = AORM::Mapping::Class(self).new(self)
      driver.load_metadata_for_entity(metadata)
      metadata
    end
  end
end
