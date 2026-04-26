require "../spec_helper"

struct PostgresPlatformBooleanTest < ASPEC::TestCase
  @platform : AORM::Platforms::Postgres = AORM::Platforms::Postgres.new

  @[DataProvider("pg_boolean_provider")]
  def test_convert_booleans_to_db_value_passes_bool_through(_database_value : String, boolean_value : Bool) : Nil
    @platform.convert_booleans_to_db_value(boolean_value).should eq boolean_value
  end

  @[DataProvider("pg_boolean_provider")]
  def test_convert_from_boolean_recognizes_string_literal(database_value : String, boolean_value : Bool) : Nil
    @platform.convert_from_boolean(database_value).should eq boolean_value
  end

  def test_convert_from_boolean_normalizes_whitespace_and_case : Nil
    @platform.convert_from_boolean("  FALSE  ").should eq false
    @platform.convert_from_boolean(" Off ").should eq false
    @platform.convert_from_boolean(" T ").should eq true
  end

  # Anything not in the false-literal set is truthy
  def test_convert_from_boolean_treats_unknown_string_as_true : Nil
    @platform.convert_from_boolean("anything else").should eq true
    @platform.convert_from_boolean("maybe").should eq true
  end

  def test_convert_from_boolean_preserves_nil : Nil
    @platform.convert_from_boolean(nil).should be_nil
  end

  def test_convert_from_boolean_passes_bool_through : Nil
    @platform.convert_from_boolean(true).should eq true
    @platform.convert_from_boolean(false).should eq false
  end

  def test_convert_booleans_to_db_value_raises_on_invalid_literal : Nil
    expect_raises(Exception, /cannot convert.+to a boolean DB value/i) do
      @platform.convert_booleans_to_db_value("my-bool")
    end
  end

  def pg_boolean_provider : Hash
    {
      "string 't'"     => {"t", true},
      "string 'true'"  => {"true", true},
      "string 'y'"     => {"y", true},
      "string 'yes'"   => {"yes", true},
      "string 'on'"    => {"on", true},
      "string '1'"     => {"1", true},
      "string 'f'"     => {"f", false},
      "string 'false'" => {"false", false},
      "string 'n'"     => {"n", false},
      "string 'no'"    => {"no", false},
      "string 'off'"   => {"off", false},
      "string '0'"     => {"0", false},
    }
  end
end
