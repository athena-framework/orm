struct Athena::ORM::BasicEntityPersister
  include Athena::ORM::EntityPersisterInterface

  private abstract struct ParameterBase; end

  private record Parameter(T) < ParameterBase, name : String, value : T, type : AORM::Types::Type

  @connection : DB::Connection
  @platform : AORM::Platforms::Platform

  @insert_sql : String? = nil
  @insert_columns : Hash(String, AORM::Metadata::ColumnBase)? = nil

  @current_persister_context : AORM::CachedPersisterContext
  @limits_handling_context : AORM::CachedPersisterContext
  @no_limits_context : AORM::CachedPersisterContext

  def initialize(@em : AORM::EntityManagerInterface, @class_metadata : AORM::Metadata::Class)
    @connection = @em.connection
    @platform = @connection.database_platform

    @no_limits_context = @current_persister_context = AORM::CachedPersisterContext.new @class_metadata, false
    @limits_handling_context = AORM::CachedPersisterContext.new @class_metadata, true
  end

  def identifier(entity : AORM::Entity) : Array(AORM::Metadata::Value)
    @class_metadata.identifier.compact_map do |field_name|
      property = @class_metadata.property(field_name).not_nil!
      property.get_value(entity).as AORM::Metadata::Value
    end
  end

  def load_by_id(id : Hash(String, Int | String)) : AORM::Entity?
    self.load id
  end

  def load(
    criteria : Hash(String, _),
    lock_mode = nil,
    limit : Int? = nil,
    order_by : Array(String)? = nil
  ) : AORM::Entity?
    self.switch_persister_context nil, limit

    sql = self.select_sql criteria, lock_mode, limit, nil, order_by
    params = self.expand_parameters criteria

    entities = [] of AORM::Entity

    @connection.query_each sql, args: params do |rs|
      entities << @class_metadata.entity_class.from_rs rs, @platform
    end

    entities.first?
  end

  def expand_parameters(criteria : Hash(String, _))
    criteria.map do |key, value|
      next if value.nil?

      self.get_values value
    end
  end

  def get_values(value : _)
    if value.is_a? Array
      new_value = [] of DB::Any

      value.each do |v|
        new_value = new_value.concat self.get_values v
      end

      new_value
    end

    # TODO: Handle static metadata?

    value
  end

  protected def select_sql(
    criteria : Hash(String, _),
    lock_mode = nil,
    limit : Int? = nil,
    offset : Int? = nil,
    order_by : Array(String)? = nil
  ) : String
    # TODO: Handle locking/joins/ordering
    conditional_sql = self.select_conditional_sql criteria
    column_list = self.select_columns_sql
    table_alias = self.sql_table_alias @class_metadata.table_name
    table_name = @class_metadata.table.quoted_qualified_name @platform

    # TODO: Handle filtering

    sql = String.build do |str|
      str << "SELECT " << column_list
      str << " FROM " << table_name << ' ' << table_alias

      unless conditional_sql.empty?
        str << " WHERE " << conditional_sql
      end

      # TODO: Add lock
    end

    @platform.modify_limit_query sql, limit, offset || 0
  end

  protected def select_conditional_sql(criteria : Hash(String, _)) : String
    criteria.join " AND " do |key, value|
      self.select_conditional_statement_sql key, value
    end
  end

  def select_conditional_statement_sql(field : String, value : _) : String
    columns = self.select_conditional_statement_column_sql field

    # TODO: Support comparison type

    idx = 1
    columns.join " AND " do |column_name|
      property = @class_metadata.property(field).not_nil!
      placeholder = "$#{idx}"

      if value.is_a? Array
        in_sql = "#{column_name} IN (#{placeholder})"

        if value.includes? nil
          idx += 1
          next "(#{in_sql} OR #{column_name} IS NULL)"
        end

        idx += 1
        next in_sql
      end

      if value.nil?
        idx += 1
        next "#{column_name} IS NULL"
      end

      idx += 1
      "#{column_name} = #{placeholder}"
    end
  end

  def select_conditional_statement_column_sql(field : String) : Array(String)
    property = @class_metadata.property(field).not_nil!

    table_alias = sql_table_alias property.table_name
    column_name = @platform.quote_identifier property.column_name

    ["#{table_alias}.#{column_name}"]

    # TODO: Handle associations
  end

  protected def select_columns_sql : String
    if col_list = @current_persister_context.select_column_list
      return col_list
    end

    @current_persister_context.select_column_list = @class_metadata.each.join ", " do |_, property|
      self.select_column_sql property
    end
  end

  protected def select_column_sql(property : AORM::Metadata::ColumnBase, calias : String = "r") : String
    column_alias = self.sql_column_alias

    sql = %(#{self.sql_table_alias property.table_name, (calias == "r" ? "" : calias)}.#{@platform.quote_identifier property.column_name})

    # TODO: Support the type altering the sql
    "#{sql} AS #{column_alias}"
  end

  def update(entity : AORM::Entity) : Nil
    table_name = @class_metadata.table_name
    update_data = self.prepare_update_data entity

    return unless update_data.has_key? table_name

    data = update_data[table_name]

    return if data.empty?

    quoted_table_name = @class_metadata.table.quoted_qualified_name @platform

    self.update_table entity, quoted_table_name, data, false

    # TODO: Handled versions
  end

  private def update_table(entity : AORM::Entity, quoted_table_name : String, update_data : Array(ParameterBase), versioned : Bool) : Nil
    set = [] of String
    params = [] of DB::Any

    update_data.each_with_index do |param, idx|
      set << "#{@platform.quote_identifier param.name} = $#{idx + 1}"
      params << param.value.value
    end

    identifier = @em.unit_of_work.entity_identifier entity
    where = [] of String

    @class_metadata.identifier.each do |id_name|
      property = @class_metadata.property(id_name).not_nil!

      where << @platform.quote_identifier property.column_name
      params << identifier[id_name].value

      # TODO: Handle associations
    end

    sql = %(UPDATE #{quoted_table_name} SET #{set.join ", "} WHERE #{where.join " = $1 AND "} = $#{update_data.size + 1})

    stmt = @connection.fetch_or_build_prepared_statement sql

    puts sql
    pp params

    stmt.exec args: params

    # TODO: handle version lock failures
  end

  protected def prepare_update_data(entity : AORM::Entity) : Hash(String, Array(ParameterBase))
    uow = @em.unit_of_work
    changeset = uow.change_set entity
    result = Hash(String, Array(ParameterBase)).new

    table_name = @class_metadata.table_name
    column_prefix = ""

    # TODO: Handle versioned properties

    changeset.each do |name, change|
      property = @class_metadata.property(name).not_nil!
      new_value = change.new

      # TODO: Handle associations and versioned properties
      column_table_name = property.table_name || table_name
      column_name = "#{column_prefix}#{property.column_name}"

      (result[column_table_name] ||= Array(ParameterBase).new) << Parameter.new column_name, new_value, property.type
    end

    result
  end

  def delete(entity : AORM::Entity) : Bool
    uow = @em.unit_of_work
    identifier = uow.entity_identifier entity
    table_name = @class_metadata.table.quoted_qualified_name @platform

    id = Hash(String, AORM::Metadata::Value).new

    @class_metadata.identifier.each do |name|
      property = @class_metadata.property(name).not_nil!
      quoted_column_name = @platform.quote_identifier property.column_name

      id[quoted_column_name] = identifier[name]

      # TODO: Handle join column FK deletion
    end

    # TODO: Use proper exception type
    raise "NO PK" if id.empty?

    columns = [] of String
    values = [] of DB::Any
    conditions = [] of String

    idx = 1
    id.each do |name, value|
      v = value.value

      if v.nil?
        conditions << @platform.is_null_expression name
        next
      end

      columns << name
      values << v
      conditions << "#{name} = $#{idx}"

      idx += 1
    end

    delete_sql = %(DELETE FROM #{table_name} WHERE #{conditions.join(" AND ")})

    puts delete_sql
    pp values

    stmt = @connection.fetch_or_build_prepared_statement delete_sql

    !stmt.exec(args: values).rows_affected.zero?
  end

  def insert(entity : AORM::Entity) : Nil
    stmt = @connection.fetch_or_build_prepared_statement self.insert_sql
    table_name = @class_metadata.table_name
    insert_data = self.prepare_insert_data entity

    puts @insert_sql
    pp insert_data

    stmt.exec args: insert_data
  end

  def insert_sql : String
    if sql = @insert_sql
      return sql
    end

    columns = self.insert_column_list
    table_name = @class_metadata.table.quoted_qualified_name @platform

    # TODO: Handle empty columns list

    quoted_columns = [] of String
    values = [] of DB::Any
    idx = 1

    columns.each do |name, metadata|
      quoted_columns << @platform.quote_identifier metadata.column_name
      values << metadata.type.to_database_value_sql "$#{idx}", @platform
      idx += 1
    end

    quoted_columns = quoted_columns.join(", ")
    values = values.join(", ")

    @insert_sql = "INSERT INTO #{table_name} (#{quoted_columns}) VALUES (#{values})"
  end

  protected def prepare_insert_data(entity : AORM::Entity) : Array
    column_prefix = ""
    table_name = @class_metadata.table_name

    @class_metadata.map do |property|
      property.get_value(entity).value
    end
  end

  protected def insert_column_list : Hash(String, AORM::Metadata::ColumnBase)
    if columns = @insert_columns
      return columns
    end

    @insert_columns = self.column_list(@class_metadata)
  end

  protected def column_list(class_metadata : AORM::Metadata::Class, column_prefix : String = "") : Hash(String, AORM::Metadata::ColumnBase)
    columns = Hash(String, AORM::Metadata::ColumnBase).new

    class_metadata.each do |property|
      if !property.has_value_generator? || !property.value_generator.try &.type.identity?
        columns["#{column_prefix}#{property.name}"] = property
      end
    end

    columns
  end

  protected def sql_column_alias : String
    @platform.sql_result_casing "c#{@current_persister_context.sql_alias_counter}"
  end

  protected def sql_table_alias(table_name : String?, assoc_name : String = "") : String
    # TODO: Allow for joins

    table_name = "#{table_name}##{assoc_name}" if table_name

    if talias = @current_persister_context.sql_table_aliases[table_name]?
      return talias
    end

    table_alias = "t#{@current_persister_context.sql_alias_counter}"

    if table_name
      @current_persister_context.sql_table_aliases[table_name] = table_alias
    end

    table_alias
  end

  private def switch_persister_context(offset : Int?, limit : Int?) : Nil
    if offset.nil? && limit.nil?
      @current_persister_context = @no_limits_context

      return
    end

    @current_persister_context = @limits_handling_context
  end
end
