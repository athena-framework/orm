require "./array_collection"

module Athena::ORM::PersistentCollectionInterface; end

# ORM-aware collection with dirty tracking and lazy loading support.
# Tracks changes since the last snapshot for computing insert/delete diffs.
class Athena::ORM::PersistentCollection(T) < Athena::ORM::AbstractLazyCollection(T)
  include PersistentCollectionInterface

  @snapshot : Array(T) = [] of T
  getter? dirty : Bool = false

  # The entity that owns this collection.
  getter owner : AORM::Entity?

  # The association mapping for this collection.
  getter! association : AORM::Mapping::Association

  getter! back_ref_field_name : String
  @collection : AORM::ArrayCollection(T)
  @em : AORM::EntityManagerInterface?
  @class_metadata : Mapping::ClassInterface?

  # Creates a PersistentCollection backed by an ArrayCollection.
  # Used by the ORM when loading entities.
  def initialize(
    em : AORM::EntityManagerInterface,
    class_metadata : Mapping::ClassInterface,
    collection : Athena::ORM::ArrayCollection(T),
  )
    @em = em
    @class_metadata = class_metadata
    @collection = collection
    @is_loaded = true
  end

  # Creates an empty PersistentCollection.
  # Primarily for testing or standalone use.
  def initialize
    @collection = AORM::ArrayCollection(T).new
    @is_loaded = true
  end

  # Creates a PersistentCollection with initial elements.
  # Primarily for testing or standalone use.
  def initialize(elements : Array(T))
    @collection = AORM::ArrayCollection(T).new(elements)
    @is_loaded = true
  end

  # Sets the owner entity and association for this collection.
  def set_owner(owner : AORM::Entity, association : AORM::Mapping::Association) : Nil
    @owner = owner
    @association = association
    @back_ref_field_name = if association.is_a?(Mapping::OwningSide)
                             association.inversed_by
                           else
                             association.as(Mapping::InverseSide).mapped_by
                           end
  end

  def each(& : T ->) : Nil
    initialize_collection
    @collection.each do |v|
      yield v
    end
  end

  def size : Int32
    initialize_collection
    @collection.size
  end

  def unsafe_fetch(index) : T
    initialize_collection
    @collection.unsafe_fetch index
  end

  # Returns the element at the given index, or nil if out of bounds.
  def []?(index : Int) : T?
    initialize_collection
    @collection[index]?
  end

  # Sets the element at the given index with dirty tracking.
  def []=(index : Int, value : T) : T
    mark_dirty
    @collection[index] = value
  end

  # Adds an element to the collection with dirty tracking.
  def <<(element : T) : self
    mark_dirty
    @collection << element
    self
  end

  # Removes an element from the collection with dirty tracking.
  def delete(element : T) : T?
    initialize_collection
    if @collection.includes?(element)
      mark_dirty
      @collection.delete(element)
    end
  end

  # Removes all elements from the collection with dirty tracking.
  def clear : Nil
    initialize_collection
    unless @collection.empty?
      mark_dirty
    end
    @collection.clear
  end

  # Returns whether the collection contains the element.
  def includes?(element : T) : Bool
    initialize_collection
    @collection.includes?(element)
  end

  # Removes an element and returns whether it was present.
  def remove_element(element : T) : Bool
    initialize_collection
    if @collection.includes?(element)
      mark_dirty
      @collection.delete(element)
      true
    else
      false
    end
  end

  def hydrate_add(element : AORM::Entity) : Nil
    # Cast and add directly to avoid overload resolution issues
    @collection << element.as(T)
  end

  # Adds an element during hydration without marking dirty.
  def hydrate_add(element : T) : Nil
    @collection << element
  end

  # Sets an element during hydration without marking dirty.
  def hydrate_set(index : Int, element : T) : Nil
    @collection[index] = element
  end

  def initialize_collection : Nil
    return if @is_loaded || @association.nil?

    # Set loaded early to prevent re-entrancy during do_initialize
    @is_loaded = true
    self.do_initialize
  end

  # Captures the current state for change detection.
  def take_snapshot : Nil
    @snapshot = @collection.to_a
    @dirty = false
  end

  # Returns a copy of the elements array.
  def to_a : Array(T)
    initialize_collection
    @collection.to_a
  end

  # Marks the collection as dirty.
  def mark_dirty : Nil
    @dirty = true
  end

  # Returns elements that were in the snapshot but are no longer present.
  def delete_diff : Array(T)
    @snapshot.reject { |e| @collection.includes?(e) }
  end

  # Returns elements that are present now but were not in the snapshot.
  def insert_diff : Array(T)
    @collection.to_a.reject { |e| @snapshot.includes?(e) }
  end

  # Returns a copy of the snapshot.
  def snapshot : Array(T)
    @snapshot.dup
  end

  # Unwraps the collection to an ArrayCollection for use outside ORM context.
  def unwrap : Collection(T)
    @collection
  end

  protected def do_initialize : Nil
    em = @em
    return unless em # Standalone collection without ORM context

    newly_added_dirty_objects = [] of T

    if @dirty
      newly_added_dirty_objects = self.unwrap.to_a
    end

    self.unwrap.clear
    em.unit_of_work.load_collection self
    self.take_snapshot

    unless newly_added_dirty_objects.empty?
      self.restore_new_objects_in_dirty_collection newly_added_dirty_objects
    end
  end

  private def restore_new_objects_in_dirty_collection(new_entities : Array(T)) : Nil
    loaded_objects = self.unwrap.to_a

    raise "TODO"
  end
end
