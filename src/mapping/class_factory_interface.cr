module Athena::ORM::Mapping::ClassFactoryInterface
  abstract def metadata(for entity_class : AORM::Entity.class) : AORM::Mapping::ClassInterface

  # Should *entity_class* have its metadata loaded?
  # abstract def transient?(entity_class : AORM::Entity.class) : Bool
end
