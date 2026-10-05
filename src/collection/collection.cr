# Marker module for ORM collections.
# Implemented by ArrayCollection and PersistentCollection.
module Athena::ORM::Collection(T)
end

# Non-generic ancestor of every collection implementation.
abstract class Athena::ORM::BaseCollection
end

# Non-generic ancestor of every persistent collection, declaring what the unit of work and persisters use through it.
# A union of different `PersistentCollection(T)` instances collapses to this class, so it must provide everything callers need.
abstract class Athena::ORM::BasePersistentCollection < Athena::ORM::BaseCollection
  # Collection implementations are generic instances, which the compiler would otherwise create one at a time while typing the program.
  # Each new one re-types every call already typed through `BaseCollection` or this class, which made compile time grow quadratically with the number of entities.
  # Declaring the collection types of every entity before any code is typed avoids that, and also guarantees these abstract classes have concrete implementations whatever order code is compiled in.
  macro finished
    {% for entity, idx in Athena::ORM::Entity.all_subclasses.reject { |t| t.abstract? || t <= Athena::ORM::Proxy } %}
      @@persistent_collection_{{idx}} : AORM::PersistentCollection({{entity.id}})? = nil
      @@array_collection_{{idx}} : AORM::ArrayCollection({{entity.id}})? = nil
    {% end %}
  end

  abstract def owner : AORM::Entity?
  abstract def association : AORM::Mapping::Association
  abstract def set_owner(owner : AORM::Entity, association : AORM::Mapping::Association) : Nil
  abstract def dirty? : Bool
  abstract def initialize_collection : Nil
  abstract def take_snapshot : Nil
  abstract def remove_element(element : AORM::Entity) : Bool
  abstract def hydrate_add(element : AORM::Entity) : Nil
  abstract def unwrap
  abstract def clone
  abstract def delete_diff
  abstract def insert_diff
end
