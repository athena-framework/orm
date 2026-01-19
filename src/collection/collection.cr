# Base interface for ORM collections.
# Extends Indexable for read access and defines abstract methods for mutation.
module Athena::ORM::Collection(T)
  include Indexable(T)

  # Adds an element to the collection.
  abstract def add(element : T) : Nil

  # Removes an element from the collection.
  # Returns the removed element, or nil if not found.
  abstract def delete(element : T) : T?

  # Removes all elements from the collection.
  abstract def clear : Nil

  # Returns whether the collection contains the element.
  def includes?(element : T) : Bool
    each do |item|
      return true if item == element
    end
    false
  end
end
