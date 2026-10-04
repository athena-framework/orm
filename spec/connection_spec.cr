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
end
