require "./sql/parser"

module Athena::ORM
  class Connection
    include DB::QueryMethods(DB::Statement)

    getter platform : Platforms::Platform
    getter wrapped : DB::Connection

    def database_platform : Platforms::Platform
      @platform
    end

    def initialize(@wrapped : DB::Connection)
      @platform = @wrapped.database_platform
    end

    # Required by DB::QueryMethods - parses SQL and returns statement with converted placeholders
    def build(query) : DB::Statement
      @wrapped.prepare(query)
    end

    def transaction(&)
      @wrapped.transaction { |tx| yield tx }
    end

    forward_missing_to @wrapped
  end
end
