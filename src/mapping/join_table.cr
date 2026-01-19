class Athena::ORM::Mapping::JoinTable
  property name : String
  property schema : String?
  property join_columns : Array(JoinColumn)
  property inverse_join_columns : Array(JoinColumn)
  property? quoted : Bool

  def initialize(
    @name : String,
    @schema : String? = nil,
    @join_columns : Array(JoinColumn) = [] of JoinColumn,
    @inverse_join_columns : Array(JoinColumn) = [] of JoinColumn,
    @quoted : Bool = false,
  )
  end

  # Returns the fully qualified table name including schema if set.
  def qualified_name : String
    @schema ? "#{@schema}.#{@name}" : @name
  end
end
