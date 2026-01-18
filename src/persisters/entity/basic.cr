require "./interface"

class Athena::ORM::Persisters::Entity::Basic
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

  def add_insert(entity : AORM::Entity) : Nil
    @queued_inserts << entity
  end

  def execute_inserts : Nil
    return if @queued_inserts.empty?

    uow = @em.unit_of_work
    id_generator = @class_metadata.id_generator
    is_post_insert_id = id_generator.post_insert?

    statement = @connection.build self.insert_sql
    table_name = @class_metadata.table_name

    @queued_inserts.each do |entity|
      insert_data = self.prepare_insert_data entity

      statement.exec args: insert_data[table_name].values

      if is_post_insert_id
        generated_id = id_generator.generate @em, entity
        id = {@class_metadata.identifier.first => generated_id}

        uow.assign_post_insert_id entity, generated_id
      else
        id = @class_metadata.identifier_values entity
      end

      if @class_metadata.requires_fetch_after_change?
        self.assign_default_version_and_upsertable_values entity, id
      end

      @queued_inserts.delete entity
    end
  end

  def owning_table(field_name : String) : String
    @class_metadata.table_name
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

  protected def assign_default_version_and_upsertable_values(entity : AORM::Entity, id : Hash(String, _)) : Nil
    values = self.fetch_version_and_not_uperstable_values @class_metadata, id
  end

  protected def fetch_version_and_not_uperstable_values(class_metadata : Mapping::ClassInterface, id : Hash(String, _)) : Nil
    raise "TODO"
  end

  def insert_sql : String
    columns = self.insert_column_list
    table_name = @quote_strategy.table_name @class_metadata, @platform

    if columns.empty?
      identity_column = @quote_strategy.column_name @class_metadata.identifier.first, @class_metadata, @platform

      return @platform.empty_identity_insert_sql table_name, identity_column
    end

    placeholders = [] of String
    columns.uniq!

    columns.each do |column|
      placeholder = "?"

      if (field_name = @class_metadata.field_names[column]?) && (column_type = @column_types[field_name]?) && (@class_metadata.field_mappings.has_key? field_name)
        type = Types::Type.get_type column_type
        placeholder = type.to_db_sql "?", @platform
      end

      placeholders << placeholder
    end

    columns = columns.join ", "
    placeholders = placeholders.join ", "

    "INSERT INTO #{table_name} (#{columns}) VALUES (#{placeholders})"
  end

  def insert_column_list : Array(String)
    columns = [] of String

    @class_metadata.field_info.each do |name, field|
      # TODO: Handle versioning
      # TODO: Handle embedded classes

      if assoc = @class_metadata.association_mappings[name]?
        if assoc.is_a?(Mapping::ToOneOwningSide)
          assoc.join_columns.each do |join_column|
            columns << @quote_strategy.join_column_name join_column, @class_metadata, @platform
          end
        end

        next
      end

      if !@class_metadata.id_generator_type.identity? || @class_metadata.identifier.first != name
        next if @class_metadata.field_mappings[name].not_insertable

        columns << @quote_strategy.column_name name, @class_metadata, @platform
        @column_types[name] = @class_metadata.field_mappings[name].type
      end
    end

    columns
  end

  def update(entity : AORM::Entity) : Nil
    table_name = @quote_strategy.table_name @class_metadata, @platform
    update_data = self.prepare_update_data entity

    return unless data = update_data[table_name]?
    return if data.empty?

    # TODO: Handle versioning
    quoted_table_name = @quote_strategy.table_name @class_metadata, @platform

    self.update_table entity, quoted_table_name, data

    if @class_metadata.requires_fetch_after_change?
      id = @class_metadata.identifier_values entity

      self.assign_default_version_and_upsertable_values entity, id
    end
  end

  protected def update_table(
    entity : AORM::Entity,
    quoted_table_name : String,
    update_data : Hash(String, _),
  ) : Nil
    set = [] of String
    params = [] of DB::Any

    update_data.each do |column_name, value|
      placeholder = "?"
      column = column_name

      if (field_name = @class_metadata.field_names[column_name]?)
        column = @quote_strategy.column_name field_name, @class_metadata, @platform

        if @class_metadata.field_mappings.has_key? field_name
          type = Types::Type.get_type @column_types[column_name]
          placeholder = type.to_db_sql "?", @platform
        end
      elsif quoted_column_name = @quoted_columns[column_name]?
        column = quoted_column_name
      end

      params << value
      set << "#{column} = #{placeholder}"
    end

    where = [] of String
    identifier = @em.unit_of_work.entity_identifier entity

    @class_metadata.identifier.each do |id_field|
      unless assoc = @class_metadata.association_mappings[id_field]?
        params << identifier[id_field].value
        where << @quote_strategy.column_name id_field, @class_metadata, @platform

        next
      end

      # TODO: Handle associations
    end

    # TODO: Handle versioning

    sql = String.build do |io|
      io << "UPDATE " << quoted_table_name
      io << " SET "
      set.join io, ", "
      io << " WHERE "
      where.join io, " = ? AND "
      io << " = ?"
    end

    result = @connection.exec sql, args: params

    if false && result.rows_affected.zero?
      raise "lock filed"
    end
  end

  def delete(entity : AORM::Entity) : Bool
    identifier = @em.unit_of_work.entity_identifier entity
    table_name = @quote_strategy.table_name @class_metadata, @platform
    id_columns = @quote_strategy.identifier_column_names @class_metadata, @platform
    id = Hash.zip id_columns, identifier.values
    types = self.class_identifier_types @class_metadata

    self.delete_join_table_records identifier, types

    values, conditions = self.delete_condition_sql identifier

    sql = String.build do |io|
      io << "DELETE FROM " << table_name

      unless conditions.empty?
        io << " WHERE "
        conditions.join io, " AND "
      end
    end

    !@connection.exec(sql, args: values).rows_affected.zero?
  end

  private def delete_condition_sql(criteria : Hash)
    values = [] of DB::Any
    conditions = [] of String

    criteria.each do |k, v|
      value = v.is_a?(Mapping::Value) ? v.value : v

      if value.nil?
        conditions << "#{k} IS NULL"

        next
      end

      values << value
      conditions << "#{k} = ?"
    end

    {values, conditions}
  end

  protected def delete_join_table_records(identifier : Hash, types : Array(String)) : Nil
    # TODO: Handle associations
  end

  protected def class_identifier_types(class_metadata : Mapping::ClassInterface) : Array(String)
    class_metadata.identifier.map do |field_name|
      types = PersisterHelper.type_of_field field_name, class_metadata, @em

      types[0]
    end
  end

  protected def prepare_insert_data(entity : AORM::Entity) : Hash(String, Hash(String, DB::Any))
    self.prepare_update_data entity, true
  end

  protected def prepare_update_data(entity : AORM::Entity, is_insert : Bool = false) : Hash(String, Hash(String, DB::Any))
    uow = @em.unit_of_work
    result = Hash(String, Hash(String, DB::Any)).new do |hash, key|
      hash[key] = Hash(String, DB::Any).new
    end

    # TODO: Handle versioning

    uow.entity_changeset(entity).each do |field, change|
      # TODO: Handle versioning
      # TODO: Handle embedded classes

      new_val = change.new.value

      unless assoc = @class_metadata.association_mappings[field]?
        fm = @class_metadata.field_mappings[field]
        column_name = fm.column_name

        if !is_insert && fm.not_updatable
          next
        end

        if is_insert && fm.not_insertable
          next
        end

        @column_types[column_name] = fm.type
        result[self.owning_table field][column_name] = new_val

        next
      end

      # TODO: Handle associations
    end

    result
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
        placeholder = type.to_db_sql placeholder, @platform
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
    fm = metadata.field_mappings[field]
    sql = "#{table_alias}.#{@quote_strategy.column_name field, metadata, @platform}"

    column_alias = nil
    # TODO: ResultSetMapping?

    unless column_alias
      column_alias = self.sql_column_alias fm.column_name
    end

    # TODO: ResultSetMapping?
    # TODO: Handle enum type columns

    type = Types::Type.get_type fm.type
    sql = type.to_db_sql sql, @platform

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
