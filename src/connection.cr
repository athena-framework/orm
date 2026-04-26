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
