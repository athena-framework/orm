require "./interface"

struct Athena::ORM::Persisters::Entity::Basic
  include Athena::ORM::Persisters::Entity::Interface

  COMPARISON_MAP = {
    "=" => "= %s",
  }

  private abstract struct ParameterBase; end

  private record Parameter(T) < ParameterBase, name : String, value : T, type : AORM::Types::Type

  @connection : AORM::Connection
  @platform : AORM::Platforms::Platform
  @quote_strategy : AORM::Mapping::QuoteStrategyInterface

  @queued_inserts = Set(AORM::Entity).new.compare_by_identity
  @column_types = Hash(String, String).new
  @quoted_columns = Hash(String, String).new

  @current_persister_context : AORM::Persisters::Entity::CachedPersisterContext
  @limits_handling_context : AORM::Persisters::Entity::CachedPersisterContext
  @no_limits_context : AORM::Persisters::Entity::CachedPersisterContext

  def initialize(@em : AORM::EntityManagerInterface, @class_metadata : AORM::Mapping::ClassInterface)
    @connection = @em.connection
    @platform = @connection.platform
    @quote_strategy = AORM::Mapping::DefaultQuoteStrategy.new

    @no_limits_context = @current_persister_context = AORM::Persisters::Entity::CachedPersisterContext.new @class_metadata, false
    @limits_handling_context = AORM::Persisters::Entity::CachedPersisterContext.new @class_metadata, true
  end

  def load_by_id(id : Hash(String, Int | String)) : AORM::Entity?
    self.load id
  end

  def load(
    criteria : Hash(String, _),
    entity : AORM::Entity? = nil,
    association : Mapping::Association? = nil,
    hints : Hash(String, String) = {} of String => String,
    lock_mode : LockMode? = nil,
    limit : Int? = nil,
    order_by : Array(String)? = nil,
  ) : AORM::Entity?
    self.switch_persister_context nil, limit
    sql = self.select_sql criteria, association, lock_mode, limit, nil, order_by
    params, types = self.expand_parameters criteria

    hydrator = @em.hydrator(!@current_persister_context.select_join_sql.empty? ? AORM::HydrationMode::Object : AORM::HydrationMode::SimpleObject)

    entities = [] of AORM::Entity

    @connection.query sql, args: params do |rs|
      entities = hydrator.hydrate_all(rs, @class_metadata, hints)
    end

    entities.first?
  end

  def exists(
    entity : AORM::Entity,

    # TODO: Handle Criteria type
    extra_conditions = nil,
  ) : Bool
    criteria = @class_metadata.identifier_values entity

    if criteria.empty?
      return false
    end

    table_alias = self.sql_table_alias @class_metadata.entity_class

    sql = String.build do |io|
      io << "SELECT 1 "
      io << self.lock_tables_sql :none
      io << " WHERE " << self.select_condition_sql criteria
    end

    params, types = self.expand_parameters criteria

    # TODO: Handle extra_conditions

    # TODO: Handle filters

    !!@connection.query_one?(sql, args: params, as: ::Int32)
  end

  def expand_parameters(criteria : Hash(String, _)) : Tuple
    params = [] of DB::Any
    types = [] of ParameterType | ArrayParameterType | String

    criteria.each do |k, v|
      next if v.nil?

      if v.is_a?(Enumerable)
        # TODO: Handle array values
      end

      types.concat PersisterHelper.infer_parameter_types k, v, @class_metadata, @em
      params.concat PersisterHelper.convert_to_parameter_value v, @em
    end

    {params, types}
  end

  protected def lock_tables_sql(lock_mode : LockMode) : String
    @platform.append_lock_hint(
      "FROM #{@quote_strategy.table_name @class_metadata, @platform} #{self.sql_table_alias @class_metadata.entity_class}",
      lock_mode
    )
  end

  protected def select_sql(
    criteria : Hash(String, _), # TODO: Handle `Criteria` obj
    association : Mapping::Association? = nil,
    lock_mode : LockMode? = nil,
    limit : Int? = nil,
    offset : Int32? = nil,
    order_by : Array(String)? = nil,
  ) : String
    self.switch_persister_context offset, limit

    join_sql = ""
    order_by_sql = ""

    # TODO: Many many to many assoc

    # TODO: Handle ordered assoc

    if order_by && !order_by.empty?
      order_by_sql = self.order_by_sql order_by, self.sql_table_alias @class_metadata.entity_class
    end

    # TODO: Handle Criteria
    condition_sql = self.select_condition_sql criteria, association

    # TODO: Handle locking
    lock_sql = ""

    column_list = self.select_columns_sql
    table_alias = self.sql_table_alias @class_metadata.entity_class
    filter_sql = self.generate_filter_condition_sql @class_metadata, table_alias
    table_name = @quote_strategy.table_name @class_metadata, @platform

    unless filter_sql.empty?
      condition_sql = condition_sql.empty? ? filter_sql : "#{condition_sql} AND #{filter_sql}"
    end

    query = String.build do |io|
      io << "SELECT " << column_list
      io << " FROM " << table_name << " " << table_alias
      io << @current_persister_context.select_join_sql << join_sql
      io << (condition_sql.empty? ? "" : " WHERE ") << condition_sql
      # TODO: Handle lock
    end

    @platform.modify_limit_query query, limit, offset || 0 # TODO: Append lock SQL
  end

  protected def generate_filter_condition_sql(metadata : Mapping::ClassInterface, target_table_alias : String) : String
    filter_clauses = [] of String

    # TODO: Handle filters

    sql = filter_clauses.join " AND "

    sql.empty? ? "" : "(#{sql})" # Wrap again to avoid "X or Y and FilterConditionSQL"
  end

  protected def select_columns_sql : String
    # TODO: Handle filters
    if (select_column_list_sql = @current_persister_context.select_column_list_sql) && true # self.filter_hash_up_to_date?
      return select_column_list_sql
    end

    column_list = [] of String
    # TODO: ResultSetMapping?

    # Add regular columns
    @class_metadata.field_names.each_value do |field|
      column_list << self.select_column_sql field, @class_metadata
    end

    @current_persister_context.select_join_sql = ""
    eager_alias_counter = 0

    # TODO: Handle associations

    sql = @current_persister_context.select_column_list_sql = column_list.join ", "
    # TODO: Update filter hash

    sql
  end

  def select_condition_statement_sql(field : String, value : _, association : Mapping::Association? = nil, comparison : String? = nil) : String
    comparison ||= value.is_a?(Enumerable) ? "IN" : "="

    selected_columns = [] of String
    columns = self.select_condition_statement_column_sql field, association

    if columns.size > 1 && comparison == "IN"
      # TODO: Try and support this
      raise "cant use in operator on composite keys"
    end

    columns.each do |column|
      placeholder = "?"

      if fm = @class_metadata.field_mappings[field]?
        type = Types::Type.get_type fm.type
        placeholder = type.to_database_value_sql placeholder, @platform
      end

      # Nil value handling
      if comparison == "=" && value.nil?
        selected_columns << "#{column} IS NULL"
        next
      end

      if comparison == "<>" && value.nil?
        selected_columns << "#{column} IS NOT NULL"
        next
      end

      # TODO: Handle IN queries

      selected_columns << "#{column} #{sprintf COMPARISON_MAP[comparison], placeholder}"
    end

    selected_columns.join " AND "
  end

  protected def select_column_sql(field : String, metadata : Mapping::ClassInterface, col_alias : String = "r") : String
    root = col_alias == "r" ? "" : col_alias
    table_alias = self.sql_table_alias metadata.entity_class, root
    field_mapping = metadata.field_mappings[field]
    sql = "#{table_alias}.#{@quote_strategy.column_name field, metadata, @platform}"

    column_alias = nil
    # TODO: ResultSetMapping?

    unless column_alias
      column_alias = self.sql_column_alias field_mapping.column_name
    end

    # TODO: ResultSetMapping?
    # TODO: Handle enum type columns

    type = Types::Type.get_type field_mapping.type
    sql = type.to_database_value_sql sql, @platform

    "#{sql} AS #{column_alias}"
  end

  protected def select_condition_sql(criteria : Hash(String, _), association : Mapping::Association? = nil) : String
    conditions = [] of String

    criteria.each do |k, v|
      conditions << self.select_condition_statement_sql k, v, association
    end

    conditions.join " AND "
  end

  protected def sql_column_alias(column_name : String) : String
    @quote_strategy.column_alias column_name, @current_persister_context.sql_alias_counter, @platform
  end

  protected def sql_table_alias(entity_class : AORM::Entity.class | Nil, assoc_name : String = "") : String
    table_name = entity_class.to_s

    if assoc_name
      table_name = "#{table_name}##{assoc_name}"
    end

    if table_alias = @current_persister_context.sql_table_aliases[table_name]?
      return table_alias
    end

    table_alias = "t#{@current_persister_context.sql_alias_counter}"

    @current_persister_context.sql_table_aliases[table_name] = table_alias
  end

  private def select_condition_statement_column_sql(field : String, association : Mapping::Association? = nil) : Array(String)
    if fm = @class_metadata.field_mappings[field]?
      # TODO: Handle inherited fields
      entity_class = @class_metadata.entity_class

      return [
        "#{self.sql_table_alias(entity_class)}.#{@quote_strategy.column_name field, @class_metadata, @platform}",
      ]
    end

    # TODO: Handle associations

    [] of String
  end

  private def switch_persister_context(offset : Int?, limit : Int?) : Nil
    if offset.nil? && limit.nil?
      @current_persister_context = @no_limits_context

      return
    end

    @current_persister_context = @limits_handling_context
  end
end
