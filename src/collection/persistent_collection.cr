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

  def initialize(
    @em : AORM::EntityManagerInterface,
    @class_metadata : Mapping::ClassInterface,
    @collection : Athena::ORM::ArrayCollection(T),
  )
    @initialized = true
  end

  # Sets the owner entity and association for this collection.
  def set_owner(owner : AORM::Entity, association : AORM::Mapping::Association) : Nil
    @owner = owner
    @association = association
    @back_ref_field_name = association.is_a?(Mapping::OwningSide) ? association.inversed_by : association.mapped_by
  end

  def each(& : T ->) : Nil
    @collection.each do |v|
      yield v
    end
  end

  def size : Int32
    @collection.size
  end

  def unsafe_fetch(index) : T
    @collection.unsafe_fetch index
  end

  def hydrate_add(element : AORM::Entity) : Nil
    self.hydrate_add element.as T
  end

  # Adds an element during hydration without marking dirty.
  # Called by the hydrator when loading from database.
  def hydrate_add(element : T) : Nil
    # @elements << element
  end

  # Sets an element during hydration without marking dirty.
  def hydrate_set(index : Int, element : T) : Nil
    # @elements[index] = element
  end

  def initialize_collection : Nil
    return if @initialized || @association.nil?

    self.do_initialize
    @initialized = true
  end

  # Captures the current state for change detection.
  # Called by the UnitOfWork after loading or flushing.
  def take_snapshot : Nil
    # @snapshot = @elements.dup
    @dirty = false
  end

  # Returns a copy of the elements array.
  def to_a : Array(T)
    initialize_collection
    # @elements.dup
    [] of T
  end

  # Marks the collection as dirty.
  def mark_dirty : Nil
    @dirty = true
  end

  # Returns elements that were in the snapshot but are no longer present.
  def delete_diff : Array(T)
    # @snapshot.reject { |e| @elements.includes?(e) }
    [] of T
  end

  # Returns elements that are present now but were not in the snapshot.
  def insert_diff : Array(T)
    # @elements.reject { |e| @snapshot.includes?(e) }
    [] of T
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
    newly_added_dirty_objects = [] of T

    if @dirty
      newly_added_dirty_objects = self.unwrap.to_a
    end

    self.unwrap.clear
    @em.unit_of_work.load_collection self
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
