require "./sql/parser"

module Athena::ORM
  class Connection
    include DB::QueryMethods(DB::Statement)

    getter platform : Platforms::Platform
    getter wrapped : DB::Connection

    # Open transactions, outermost first.
    # Nested ones are savepoints within the outer transaction.
    @transactions = [] of DB::Transaction

    def initialize(@wrapped : DB::Connection)
      @platform = @wrapped.database_platform
    end

    def database_platform : Platforms::Platform
      @platform
    end

    # Boxed values already hold a type's Crystal-side value, so they pass through unchanged.
    def convert_to_crystal_value(value : _, type : String?)
      return value if value.is_a?(Mapping::Opaque)

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

    # Executes *sql*, binding each of *params* converted through the type at the same position in *types*, and returns the result set.
    # The caller is responsible for closing it.
    def execute_query(sql : String, params : Array, types : Array(String?)) : DB::ResultSet
      self.query sql, args: self.convert_parameters(params, types)
    end

    # Executes *sql* like `#execute_query`, returning the first column of the first row, or `nil` when there are no rows.
    def fetch_one(sql : String, params : Array, types : Array(String?))
      self.execute_query sql, params, types do |rs|
        rs.move_next ? rs.read : nil
      end
    end

    # The driver picks each parameter's encoding from its runtime class, so only the value is converted; there is no separate binding type.
    # Parameters may be wrapped in a `Mapping::Value`, and converting is what narrows them to something the driver can bind.
    private def convert_parameters(params : Array, types : Array(String?)) : Array(DB::Any)
      Array(DB::Any).new(params.size) do |idx|
        param = params[idx]
        value = param.is_a?(Mapping::Value) ? param.value : param
        converted = if value.is_a?(Mapping::Opaque)
                      value.to_db types[idx]?.try { |type| Types::Type.get_type type }, self.database_platform
                    else
                      self.convert_to_database_value value, types[idx]?
                    end

        unless converted.is_a?(DB::Any)
          raise "Cannot bind parameter #{idx + 1}: #{types[idx]? ? "type '#{types[idx]?}'" : "no type"} converted #{value.class} to #{converted.class}, which the driver cannot bind."
        end

        converted
      end
    end

    # Required by DB::QueryMethods - prepares the provided SQL and returns a build statement after any required processing.
    def build(query) : DB::Statement
      @wrapped.prepare(query)
    end

    # Starts a transaction, or a savepoint if one is already active.
    def begin_transaction : Nil
      @transactions << (@transactions.last?.try(&.begin_transaction) || @wrapped.begin_transaction)
    end

    # Commits the innermost transaction, releasing its savepoint if it's nested.
    def commit : Nil
      transaction = @transactions.pop? || raise DB::Error.new "There is no active transaction."

      begin
        transaction.commit
      ensure
        # Resets the driver's transaction state if the commit failed; a failed commit still ends the transaction.
        transaction.close
      end
    end

    # Rolls back the innermost transaction, or to its savepoint if it's nested.
    def rollback : Nil
      transaction = @transactions.pop? || raise DB::Error.new "There is no active transaction."

      begin
        transaction.rollback
      ensure
        transaction.close
      end
    end

    def transaction_active? : Bool
      !@transactions.empty?
    end

    def transaction_nesting_level : Int32
      @transactions.size
    end

    # Runs the block in a transaction, or a savepoint if one is already active.
    # Commits if the block returns, returning its value, and rolls back if it raises.
    def transactional(& : self -> T) : T forall T
      self.begin_transaction

      begin
        result = yield self
      rescue ex
        self.rollback
        raise ex
      end

      self.commit

      result
    end

    forward_missing_to @wrapped
  end
end
