require "./spec_helper"

struct ConnectionTest < ASPEC::TestCase
  @wrapped : MockConnection
  @connection : AORM::Connection

  def initialize
    @wrapped = MockConnection.new
    @connection = AORM::Connection.new @wrapped
  end

  def test_convert_to_database_value_uses_the_registered_type : Nil
    @connection.convert_to_database_value("abc", Rot13Type::NAME).should eq "nop"
  end

  def test_convert_to_database_value_passes_untyped_values_through : Nil
    @connection.convert_to_database_value("abc", nil).should eq "abc"
  end

  def test_execute_statement_binds_parameters_converted_through_their_types : Nil
    @connection.execute_statement "UPDATE t SET a = ?, b = ? WHERE c = ?", ["abc", 7, "xyz"], [Rot13Type::NAME, nil, Rot13Type::NAME]

    @wrapped.executed_statements.last.should eq({"UPDATE t SET a = ?, b = ? WHERE c = ?", ["nop", 7, "klm"]})
  end

  # A boxed value object converts through its type before binding.
  def test_execute_statement_binds_boxed_values_converted_through_their_types : Nil
    param = AORM::Mapping::SingleValue.new AORM::Mapping.box(CustomIdObject.new("abc"))

    @connection.execute_statement "UPDATE t SET a = ?", [param], [CustomIdObjectType::NAME]

    @wrapped.executed_statements.last.should eq({"UPDATE t SET a = ?", ["abc"]})
  end

  def test_execute_statement_returns_the_affected_row_count : Nil
    @connection.execute_statement("DELETE FROM t", [] of DB::Any, [] of String?).should eq 1
  end

  def test_execute_query_binds_parameters_converted_through_their_types : Nil
    @connection.execute_query("SELECT * FROM t WHERE a = ?", ["abc"], [Rot13Type::NAME]) { }

    @wrapped.executed_statements.last.should eq({"SELECT * FROM t WHERE a = ?", ["nop"]})
  end

  def test_execute_query_returns_the_block_value : Nil
    @connection.execute_query("SELECT 1", [] of DB::Any, [] of String?) { :done }.should eq :done
  end

  def test_execute_query_without_a_block_returns_the_result_set : Nil
    rs = @connection.execute_query "SELECT * FROM t WHERE a = ?", ["abc"], [Rot13Type::NAME]
    rs.close

    @wrapped.executed_statements.last.should eq({"SELECT * FROM t WHERE a = ?", ["nop"]})
  end

  def test_fetch_one_returns_the_first_column_of_the_first_row : Nil
    @wrapped.queue_result [{"c" => 3_i64, "d" => 4_i64} of String => DB::Any]

    @connection.fetch_one("SELECT c, d FROM t WHERE a = ?", ["abc"], [Rot13Type::NAME]).should eq 3_i64
    @wrapped.executed_statements.last[1].should eq ["nop"]
  end

  def test_fetch_one_returns_nil_without_rows : Nil
    @wrapped.queue_result [] of Hash(String, DB::Any)

    @connection.fetch_one("SELECT c FROM t", [] of DB::Any, [] of String?).should be_nil
  end
end
