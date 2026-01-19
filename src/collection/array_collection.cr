require "./collection"

# A simple wrapper around Array implementing the Collection interface.
class Athena::ORM::ArrayCollection(T)
  include Athena::ORM::Collection
  include Indexable(T)

  @elements : Array(T)

  def initialize(elements : Array(T) = [] of T)
    @elements = elements.dup
  end

  def self.new(elements : Enumerable(T))
    new elements.to_a
  end

  # Returns the number of elements in the collection.
  def size : Int32
    @elements.size
  end

  # Returns the element at the given index.
  # Raises IndexError if the index is out of bounds.
  def unsafe_fetch(index : Int) : T
    @elements.unsafe_fetch(index)
  end

  # Returns the element at the given index, or nil if out of bounds.
  def []?(index : Int) : T?
    @elements[index]?
  end

  # Sets the element at the given index.
  def []=(index : Int, value : T) : T
    @elements[index] = value
  end

  # Adds an element to the collection.
  def add(element : T) : Nil
    @elements << element
  end

  # Adds an element to the collection (alias for add).
  def <<(element : T) : self
    add(element)
    self
  end

  # Removes an element from the collection.
  # Returns the removed element, or nil if not found.
  def delete(element : T) : T?
    @elements.delete(element)
  end

  # Removes all elements from the collection.
  def clear : Nil
    @elements.clear
  end

  # Returns whether the collection contains the element.
  def includes?(element : T) : Bool
    @elements.includes?(element)
  end

  # Returns the first element, or nil if empty.
  def first? : T?
    @elements.first?
  end

  # Returns the last element, or nil if empty.
  def last? : T?
    @elements.last?
  end

  # Returns a copy of the elements array.
  def to_a : Array(T)
    @elements.dup
  end
end
