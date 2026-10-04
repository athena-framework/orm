require "./sql/parser"

module Athena::ORM
  class Connection
    include DB::QueryMethods(DB::Statement)

    getter platform : Platforms::Platform
    getter wrapped : DB::Connection

    def initialize(@wrapped : DB::Connection)
      @platform = @wrapped.database_platform
    end

    def database_platform : Platforms::Platform
      @platform
    end

    def convert_to_crystal_value(value : _, type : String?)
      Types::Type.get_type(type.not_nil!).to_crystal_value(value, self.database_platform)
    end

    # Converts *value* to its database representation through the `Types::Type` registered as *type*.
    # Values without a type are returned unchanged.
    def convert_to_database_value(value : _, type : String?)
      return value unless type

      Types::Type.get_type(type).to_db value, self.database_platform
    end

    # Executes *sql*, binding each of *params* converted through the type at the same position in *types*, and returns the number of affected rows.
    def execute_statement(sql : String, params : Array, types : Array(String?)) : Int64
      self.exec(sql, args: self.convert_parameters(params, types)).rows_affected
    end

    # Executes *sql*, binding each of *params* converted through the type at the same position in *types*, and yields the result set.
    # Returns the block's value.
    def execute_query(sql : String, params : Array, types : Array(String?), &)
      self.query sql, args: self.convert_parameters(params, types) do |rs|
        yield rs
      end
    end

    # The driver picks each parameter's encoding from its runtime class, so only the value is converted; there is no separate binding type.
    private def convert_parameters(params : Array, types : Array(String?)) : Array(DB::Any)
      Array(DB::Any).new(params.size) do |idx|
        self.convert_to_database_value(params[idx], types[idx]?).as DB::Any
      end
    end

    # Required by DB::QueryMethods - prepares the provided SQL and returns a build statement after any required processing.
    def build(query) : DB::Statement
      @wrapped.prepare(query)
    end

    def transaction(&)
      @wrapped.transaction { |tx| yield tx }
    end

    forward_missing_to @wrapped
  end
end
