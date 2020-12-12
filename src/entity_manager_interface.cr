module Athena::ORM::EntityManagerInterface
  abstract def find(entity_class : AORM::Entity.class, id : _) : AORM::Entity?
  abstract def find!(entity_class : AORM::Entity.class, id : _) : AORM::Entity
  abstract def persist(entity : AORM::Entity) : Nil
  abstract def remove(entity : AORM::Entity) : Nil
  abstract def clear(entity_class : AORM::Entity.class | Nil = nil) : Nil
  abstract def refresh(entity : AORM::Entity) : Nil
  abstract def flush : Nil
  abstract def repository(entity_class : AORM::Entity.class) : AORM::RepositoryInterface
  abstract def contains(entity : AORM::Entity) : Bool

  abstract def connection : DB::Database
  abstract def transaction(& : DB::Transaction ->) : Nil

  abstract def unit_of_work # : AORM::UnitOfWork

  abstract def close : Nil
  abstract def closed? : Bool
  abstract def copy(entity : AORM::Entity, deep : Bool = false) : AORM::Entity
end
