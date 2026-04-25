require "./spec_helper"

# NOTE: only `find`, `find!`, and `find_one_by` are exercised here. `find_by`,
# `find_all`, and `count` delegate to persister methods that aren't yet
# implemented on the Basic persister (tracked as #26 / #32).
struct EntityRepositoryTest < ASPEC::TestCase
  @em : MockEntityManager
  @uow : MockUnitOfWork
  @persister : MockEntityPersister

  def initialize
    @em = MockEntityManager.new(MockConnection.new)
    @uow = MockUnitOfWork.new @em
    @em.uow_mock = @uow
    @persister = MockEntityPersister.new @em, @em.class_metadata(CmsPhonenumber)
    @uow.set_entity_persister CmsPhonenumber, @persister
  end

  def test_find_with_a_scalar_id_wraps_it_into_a_hash_for_the_persister : Nil
    expected = CmsPhonenumber.new
    expected.phonenumber = "555-0001"
    @persister.mock_load_by_id_result = expected

    result = repository.find("555-0001")

    result.should be expected
    @persister.load_by_id_calls.size.should eq 1
    # EntityManager wraps the scalar into `{single_id_field => value}` before
    # forwarding — ensures composite-key entities can stay on the same code path.
    @persister.load_by_id_calls.first.should eq({"phonenumber" => "555-0001"})
  end

  def test_find_returns_nil_when_persister_finds_no_match : Nil
    @persister.mock_load_by_id_result = nil

    repository.find("missing").should be_nil
  end

  def test_find_returns_an_existing_entity_from_the_identity_map_without_hitting_the_persister : Nil
    cached = CmsPhonenumber.new
    cached.phonenumber = "555-0002"
    @uow.register_managed cached, {"phonenumber" => "555-0002"}, {"phonenumber" => "555-0002"}

    result = repository.find("555-0002")

    result.should be cached
    # Identity-map hit short-circuits before the persister gets called.
    @persister.load_by_id_calls.should be_empty
  end

  def test_find_bang_raises_no_result_when_the_entity_is_missing : Nil
    @persister.mock_load_by_id_result = nil

    expect_raises(AORM::Exceptions::NoResult) do
      repository.find!("missing")
    end
  end

  def test_find_one_by_forwards_criteria_and_pins_limit_to_one : Nil
    expected = CmsPhonenumber.new
    expected.phonenumber = "555-0003"
    @persister.mock_load_result = expected

    criteria = {"phonenumber" => "555-0003"}.transform_values &.as(DB::Any | Array(DB::Any))
    result = repository.find_one_by(criteria)

    result.should be expected
    @persister.load_calls.size.should eq 1
    @persister.load_calls.first.criteria["phonenumber"].should eq "555-0003"
    @persister.load_calls.first.limit.should eq 1
  end

  def test_find_one_by_returns_nil_when_persister_finds_no_match : Nil
    @persister.mock_load_result = nil

    criteria = {"phonenumber" => "x"}.transform_values &.as(DB::Any | Array(DB::Any))
    repository.find_one_by(criteria).should be_nil
  end

  def test_find_one_by_with_keyword_args_converts_symbol_keys_to_strings : Nil
    @persister.mock_load_result = nil

    repository.find_one_by(phonenumber: "555-0004")

    @persister.load_calls.first.criteria.has_key?("phonenumber").should be_true
  end

  private def repository : AORM::EntityRepository(CmsPhonenumber)
    AORM::EntityRepository(CmsPhonenumber).new(@em, @em.class_metadata(CmsPhonenumber))
  end
end
