# Executes native SQL queries with explicit result set mapping.
class Athena::ORM::NativeQuery
  @parameters = {} of String | Int32 => {DB::Any, String?}

  def initialize(
    @em : EntityManagerInterface,
    @sql : String,
    @rsm : Query::ResultSetMapping,
  )
  end

  # Sets a query parameter, converted through the `Types::Type` named *type* when bound.
  # Without a *type*, one is inferred from *value*.
  def set_parameter(key : String | Int32, value : DB::Any, type : String? = nil) : self
    @parameters[key] = {value, type || Query::ParameterTypeInferer.infer_type(value)}
    self
  end

  # Returns the SQL string.
  def sql : String
    @sql
  end

  # Returns the result set mapping.
  def result_set_mapping : Query::ResultSetMapping
    @rsm
  end

  # Executes the query and returns all results.
  def get_result : Array(Entity)
    execute_and_hydrate
  end

  # Executes the query and returns exactly one result.
  # Raises NoResult if no rows found.
  # Raises NonUniqueResult if more than one row found.
  def get_single_result : Entity
    results = get_result
    raise Exceptions::NoResult.new if results.empty?
    raise Exceptions::NonUniqueResult.new if results.size > 1
    results.first
  end

  # Executes the query and returns one result or nil.
  # Raises NonUniqueResult if more than one row found.
  def get_one_or_nil_result : Entity?
    results = get_result
    raise Exceptions::NonUniqueResult.new if results.size > 1
    results.first?
  end

  private def execute_and_hydrate : Array(Entity)
    params, types = build_params
    hydration_mode = @rsm.joined_aliases.empty? ? HydrationMode::SimpleObject : HydrationMode::Object
    hydrator = @em.hydrator(hydration_mode)

    entities = [] of Entity

    @em.connection.execute_query(@sql, params, types) do |rs|
      entities = hydrator.hydrate_all(rs, @rsm)
    end

    entities
  end

  # Positional parameters bind in position order, regardless of the order they were set in.
  private def build_params : {Array(DB::Any), Array(String?)}
    parameters = @parameters.to_a

    if @parameters.keys.all?(Int32)
      parameters.sort_by! { |(key, _)| key.as(Int32) }
    end

    {parameters.map { |(_, (value, _))| value }, parameters.map { |(_, (_, type))| type }}
  end
end
