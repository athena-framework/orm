require "./array_collection"

# ORM-aware collection with dirty tracking and lazy loading support.
# Tracks changes since the last snapshot for computing insert/delete diffs.
class Athena::ORM::PersistentCollection(T)
  include Athena::ORM::Collection
  include Indexable(T)

  @elements : Array(T)
  @snapshot : Array(T)
  getter? dirty : Bool = false
  property? initialized : Bool = false

  # The entity that owns this collection.
  getter owner : AORM::Entity?

  # The association mapping for this collection.
  getter! association : AORM::Mapping::Association?

  def initialize
    @elements = [] of T
    @snapshot = [] of T
  end

  def initialize(elements : Array(T))
    @elements = elements.dup
    @snapshot = [] of T
  end

  def initialize(elements : Enumerable(T))
    @elements = elements.to_a
    @snapshot = [] of T
  end

  def initialize(@owner : AORM::Entity, @association : AORM::Mapping::Association)
    @elements = [] of T
    @snapshot = [] of T
  end

  # Returns the number of elements in the collection.
  def size : Int32
    @elements.size
  end

  # Returns the element at the given index.
  def unsafe_fetch(index : Int) : T
    @elements.unsafe_fetch(index)
  end

  # Returns the element at the given index, or nil if out of bounds.
  def []?(index : Int) : T?
    @elements[index]?
  end

  # Sets the element at the given index.
  def []=(index : Int, value : T) : T
    @dirty = true
    @elements[index] = value
  end

  # Adds an element to the collection.
  def add(element : T) : Nil
    @elements << element
    @dirty = true
  end

  # Adds an element to the collection (alias for add).
  def <<(element : T) : self
    add(element)
    self
  end

  # Removes an element from the collection.
  # Returns the removed element, or nil if not found.
  def delete(element : T) : T?
    if result = @elements.delete(element)
      @dirty = true
      result
    end
  end

  # Removes all elements from the collection.
  def clear : Nil
    @dirty = true unless @elements.empty?
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

  # Captures the current state for change detection.
  # Called by the UnitOfWork after loading or flushing.
  def take_snapshot : Nil
    @snapshot = @elements.dup
    @dirty = false
  end

  # Marks the collection as dirty.
  def mark_dirty : Nil
    @dirty = true
  end

  # Returns elements that were in the snapshot but are no longer present.
  def delete_diff : Array(T)
    @snapshot.reject { |e| @elements.includes?(e) }
  end

  # Returns elements that are present now but were not in the snapshot.
  def insert_diff : Array(T)
    @elements.reject { |e| @snapshot.includes?(e) }
  end

  # Returns a copy of the snapshot.
  def snapshot : Array(T)
    @snapshot.dup
  end

  # Sets the owner entity and association for this collection.
  def set_owner(owner : AORM::Entity, association : AORM::Mapping::Association) : Nil
    @owner = owner
    @association = association
  end

  # Adds an element during hydration without marking dirty.
  # Called by the hydrator when loading from database.
  def hydrate_add(element : T) : Nil
    @elements << element
  end

  # Sets an element during hydration without marking dirty.
  def hydrate_set(index : Int, element : T) : Nil
    @elements[index] = element
  end

  # Removes an entity from the collection.
  # Called by UnitOfWork when an entity is removed.
  def remove_element(element : T) : Bool
    if @elements.delete(element)
      @dirty = true
      true
    else
      false
    end
  end

  # Unwraps the collection to an ArrayCollection for use outside ORM context.
  def unwrap : ArrayCollection(T)
    ArrayCollection(T).new(@elements)
  end
end
