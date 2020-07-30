module Athena::ORM::EntityPersisterInterface
  abstract def inserts : Array(String)
  abstract def insert_sql : String
  # abstract def select_sql
  abstract def insert(entity : AORM::Entity)
end
