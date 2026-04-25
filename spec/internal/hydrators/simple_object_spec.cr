require "../../spec_helper"

struct SimpleObjectHydratorTest < ASPEC::TestCase
  # Single root entity, single row → exactly one entity in the result.
  def test_hydrates_a_single_row_into_one_entity : Nil
    em = MockEntityManager.new(MockConnection.new)
    rsm = AORM::Query::ResultSetMapping.new
    rsm.add_root_entity CmsPhonenumber, "p"
    rsm.add_field_result "p", "p__phonenumber", "phonenumber"

    rs = FakeResultSet.new([
      {"p__phonenumber" => "555-0100".as(DB::Any)},
    ])

    result = AORM::Internal::Hydrators::SimpleObject.new(em).hydrate_all(rs, rsm)

    result.size.should eq 1
    result[0].should be_a CmsPhonenumber
    result[0].as(CmsPhonenumber).phonenumber.should eq "555-0100"
  end

  def test_hydrates_multiple_rows_into_multiple_entities : Nil
    em = MockEntityManager.new(MockConnection.new)
    rsm = AORM::Query::ResultSetMapping.new
    rsm.add_root_entity CmsPhonenumber, "p"
    rsm.add_field_result "p", "p__phonenumber", "phonenumber"

    rs = FakeResultSet.new([
      {"p__phonenumber" => "555-0001".as(DB::Any)},
      {"p__phonenumber" => "555-0002".as(DB::Any)},
      {"p__phonenumber" => "555-0003".as(DB::Any)},
    ])

    result = AORM::Internal::Hydrators::SimpleObject.new(em).hydrate_all(rs, rsm)

    result.map(&.as(CmsPhonenumber).phonenumber).should eq ["555-0001", "555-0002", "555-0003"]
  end

  # Doctrine: testExtraFieldInResultSetShouldBeIgnore. Columns the RSM hasn't
  # mapped (e.g., a window-function `rownum` tagged on by the platform) should
  # be silently dropped instead of raising.
  def test_extra_columns_in_the_result_set_are_ignored : Nil
    em = MockEntityManager.new(MockConnection.new)
    rsm = AORM::Query::ResultSetMapping.new
    rsm.add_root_entity CmsPhonenumber, "p"
    rsm.add_field_result "p", "p__phonenumber", "phonenumber"

    rs = FakeResultSet.new([
      {
        "p__phonenumber" => "555-0200".as(DB::Any),
        "rownum"         => "1".as(DB::Any),
      },
    ])

    result = AORM::Internal::Hydrators::SimpleObject.new(em).hydrate_all(rs, rsm)

    result.size.should eq 1
    result[0].as(CmsPhonenumber).phonenumber.should eq "555-0200"
  end

  # The hydrator's `prepare` step asserts that the RSM models a single root
  # entity — anything richer needs the full ObjectHydrator.
  def test_prepare_rejects_an_rsm_with_more_than_one_alias : Nil
    em = MockEntityManager.new(MockConnection.new)
    rsm = AORM::Query::ResultSetMapping.new
    rsm.add_root_entity CmsPhonenumber, "p"
    rsm.add_root_entity CmsUser, "u"

    rs = FakeResultSet.new([] of Hash(String, DB::Any))

    expect_raises(Exception, /more than one object result/) do
      AORM::Internal::Hydrators::SimpleObject.new(em).hydrate_all(rs, rsm)
    end
  end
end
