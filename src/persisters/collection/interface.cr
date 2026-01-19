module Athena::ORM::Persisters::Collection::Interface
  abstract def delete(collection : AORM::PersistentCollection) : Nil
  abstract def update(collection : AORM::PersistentCollection) : Nil
end
