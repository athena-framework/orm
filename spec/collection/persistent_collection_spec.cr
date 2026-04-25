require "../spec_helper"

struct PersistentCollectionTest < ASPEC::TestCase
  def test_basic_array_operations : Nil
    collection = AORM::PersistentCollection(Int32).new

    collection.size.should eq 0
    collection.empty?.should be_true

    collection << 1 << 2 << 3

    collection.size.should eq 3
    collection.empty?.should be_false
    collection[0].should eq 1
    collection[1].should eq 2
    collection[2].should eq 3
  end

  def test_includes? : Nil
    collection = AORM::PersistentCollection(String).new(["foo", "bar"])

    collection.includes?("foo").should be_true
    collection.includes?("baz").should be_false
  end

  def test_delete : Nil
    collection = AORM::PersistentCollection(String).new(["a", "b", "c"])

    deleted = collection.delete("b")

    deleted.should eq "b"
    collection.size.should eq 2
    collection.includes?("b").should be_false
  end

  def test_clear : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])

    collection.clear

    collection.size.should eq 0
    collection.empty?.should be_true
  end

  def test_is_dirty_after_add : Nil
    collection = AORM::PersistentCollection(Int32).new
    collection.take_snapshot

    collection.dirty?.should be_false

    collection << 1

    collection.dirty?.should be_true
  end

  def test_is_dirty_after_delete : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    collection.take_snapshot

    collection.dirty?.should be_false

    collection.delete(2)

    collection.dirty?.should be_true
  end

  def test_is_dirty_after_clear : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    collection.take_snapshot

    collection.dirty?.should be_false

    collection.clear

    collection.dirty?.should be_true
  end

  def test_is_dirty_after_index_assignment : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    collection.take_snapshot

    collection.dirty?.should be_false

    collection[1] = 99

    collection.dirty?.should be_true
  end

  def test_clear_empty_not_dirty : Nil
    collection = AORM::PersistentCollection(Int32).new
    collection.take_snapshot

    collection.clear

    collection.dirty?.should be_false
  end

  def test_take_snapshot_resets_dirty : Nil
    collection = AORM::PersistentCollection(Int32).new
    collection.take_snapshot

    collection << 1

    collection.dirty?.should be_true

    collection.take_snapshot

    collection.dirty?.should be_false
  end

  def test_delete_diff : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    collection.take_snapshot

    collection.delete(1)
    collection.delete(3)

    diff = collection.delete_diff

    diff.should eq [1, 3]
  end

  def test_insert_diff : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2])
    collection.take_snapshot

    collection << 3
    collection << 4

    diff = collection.insert_diff

    diff.should eq [3, 4]
  end

  def test_mixed_operations_diff : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    collection.take_snapshot

    collection.delete(1)
    collection << 4
    collection << 5

    collection.delete_diff.should eq [1]
    collection.insert_diff.should eq [4, 5]
  end

  def test_snapshot : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    collection.take_snapshot

    snapshot = collection.snapshot

    snapshot.should eq [1, 2, 3]

    # Modifying snapshot shouldn't affect original
    snapshot << 4
    collection.snapshot.should eq [1, 2, 3]
  end

  def test_remove_element : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    collection.take_snapshot

    result = collection.remove_element(2)

    result.should be_true
    collection.includes?(2).should be_false
    collection.dirty?.should be_true
  end

  def test_remove_element_nonexistent : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    collection.take_snapshot

    result = collection.remove_element(99)

    result.should be_false
    collection.dirty?.should be_false
  end

  def test_unwrap : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])

    unwrapped = collection.unwrap

    unwrapped.should be_a AORM::ArrayCollection(Int32)
    unwrapped.to_a.should eq [1, 2, 3]
  end

  def test_iteration : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    result = [] of Int32

    collection.each do |item|
      result << item
    end

    result.should eq [1, 2, 3]
  end

  def test_to_a_returns_copy : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])

    result = collection.to_a

    result.should eq [1, 2, 3]

    # Modifying returned array shouldn't affect collection
    result << 4
    result.clear

    collection.size.should eq 3
    collection.to_a.should eq [1, 2, 3]
  end

  def test_hydrate_add_does_not_mark_dirty : Nil
    collection = AORM::PersistentCollection(Int32).new
    collection.take_snapshot

    collection.dirty?.should be_false

    collection.hydrate_add(1)
    collection.hydrate_add(2)

    collection.dirty?.should be_false
    collection.size.should eq 2
    collection[0].should eq 1
    collection[1].should eq 2
  end

  def test_hydrate_set_does_not_mark_dirty : Nil
    collection = AORM::PersistentCollection(Int32).new([1, 2, 3])
    collection.take_snapshot

    collection.dirty?.should be_false

    collection.hydrate_set(1, 99)

    collection.dirty?.should be_false
    collection[1].should eq 99
  end

  def test_restore_new_objects_after_lazy_init_keeps_unloaded_and_marks_dirty : Nil
    pre_added = TestEntityForRestore.new(1)
    loaded = TestEntityForRestore.new(2)

    collection = AORM::PersistentCollection(TestEntityForRestore).new([loaded])
    collection.take_snapshot
    # Drop dirty back to false so we can later assert restore is what re-marks it.

    RestoreInvoker.invoke(collection, [pre_added])

    items = collection.to_a
    items.size.should eq 2
    items.any?(&.same?(pre_added)).should be_true
    collection.dirty?.should be_true
  end

  def test_restore_new_objects_skips_when_all_already_loaded : Nil
    pre_added = TestEntityForRestore.new(7)

    # Same instance appears in the loaded set, so restore should be a no-op.
    collection = AORM::PersistentCollection(TestEntityForRestore).new([pre_added])
    collection.take_snapshot

    RestoreInvoker.invoke(collection, [pre_added])

    collection.to_a.size.should eq 1
    collection.dirty?.should be_false
  end

  def test_clone_copies_elements_to_independent_backing : Nil
    a = TestEntityForRestore.new(1)
    b = TestEntityForRestore.new(2)

    original = AORM::PersistentCollection(TestEntityForRestore).new([a, b])

    copy = original.clone

    copy.to_a.should eq [a, b]
    # Mutating one side must not affect the other.
    copy << TestEntityForRestore.new(3)
    original.to_a.size.should eq 2
  end

  def test_clone_drops_owner_and_marks_dirty : Nil
    original = AORM::PersistentCollection(TestEntityForRestore).new([TestEntityForRestore.new(1)])
    original.take_snapshot
    original.dirty?.should be_false

    copy = original.clone

    # The clone is detached: no owner, no snapshot, dirty so the next flush
    # will persist it for whichever entity becomes the new owner.
    copy.owner.should be_nil
    copy.dirty?.should be_true
    copy.snapshot.should be_empty
  end
end

# Plain reference-typed value object so the collection's identity-based dedup
# (uses `same?`) has something to compare. Avoids pulling AORM::Entity into a
# pure collection-level test.
private class TestEntityForRestore
  getter id : Int32

  def initialize(@id : Int32); end
end

# Friend-of-the-collection: drives the protected restore path without requiring
# a subclass that re-declares `@is_loaded` (which Crystal's two-level inheritance
# inference around PersistentCollection makes awkward in tests).
private class RestoreInvoker < AORM::PersistentCollection(TestEntityForRestore)
  def self.invoke(target : AORM::PersistentCollection(TestEntityForRestore), new_entities : Array(TestEntityForRestore)) : Nil
    target.restore_new_objects_in_dirty_collection new_entities
  end
end
