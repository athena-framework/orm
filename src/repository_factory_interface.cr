module Athena::ORM::RepositoryFactoryInterface
  abstract def repository(em : AORM::EntityManagerInterface, entity_class : AORM::Entity.class)
end
