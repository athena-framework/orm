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
end
