require "./interface"

struct Athena::ORM::Persisters::Entity::Basic
  include Athena::ORM::Persisters::Entity::Interface

  private abstract struct ParameterBase; end

  private record Parameter(T) < ParameterBase, name : String, value : T, type : AORM::Types::Type

  @connection : DB::Connection
  @platform : AORM::Platforms::Platform

  @insert_sql : String? = nil
  @insert_columns : Hash(String, AORM::Mapping::ColumnMetadata)? = nil

  @current_persister_context : AORM::Persisters::Entity::CachedPersisterContext
  @limits_handling_context : AORM::Persisters::Entity::CachedPersisterContext
  @no_limits_context : AORM::Persisters::Entity::CachedPersisterContext

  def initialize(@em : AORM::EntityManagerInterface, @class_metadata : AORM::Mapping::ClassBase)
    @connection = @em.connection
    @platform = @connection.database_platform

    @no_limits_context = @current_persister_context = AORM::Persisters::Entity::CachedPersisterContext.new @class_metadata, false
    @limits_handling_context = AORM::Persisters::Entity::CachedPersisterContext.new @class_metadata, true
  end

  def identifier(entity : AORM::Entity) : Array(AORM::Mapping::Value)
    @class_metadata.identifier.compact_map do |field_name|
      property = @class_metadata.property(field_name).not_nil!
      property.get_value(entity).as AORM::Mapping::Value
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

    sql = @platform.modify_sql_placeholders self.select_sql criteria, lock_mode, limit, nil, order_by
    params = self.expand_parameters criteria

    puts sql
    pp params

    hydrator = @em.hydrator (!!@current_persister_context.select_join_sql ? AORM::HydrationMode::Object : AORM::HydrationMode::SimpleObject)

    # results = hydrator.hydrate_all @connection.query(sql, args: params), @class_metadata

    # pp results

    entities = [] of AORM::Entity

    # TODO: Handle hints?

    @connection.query_all sql, args: params do |rs|
      if entity = hydrator.hydrate rs, @class_metadata
        entities << entity
      end
    end

    entities.first?
  end

  def expand_parameters(criteria : Hash(String, _))
    criteria.map do |_key, value|
      next if value.nil?

      self.get_values value
    end.flatten
  end

  def get_values(value : _)
    if value.is_a? Array
      new_value = [] of DB::Any

      value.each do |v|
        new_value = new_value.concat self.get_values v
      end

      return new_value
    end

    # TODO: Handle static metadata?

    [value]
  end

  def load_all(
    criteria : Hash(String, _),
    order_by : Array(String)? = nil,
    limit : Int? = nil,
    offset : Int? = nil
  ) : Array(AORM::Entity)
    self.switch_persister_context offset, limit

    sql = @platform.modify_sql_placeholders self.select_sql criteria, limit: limit, offset: offset, order_by: order_by
    params = self.expand_parameters criteria

    puts sql
    pp params

    entities = [] of AORM::Entity

    # TODO: Handle hints?

    @connection.query_each sql, args: params do |rs|
      entities << @class_metadata.entity_class.from_rs @class_metadata, rs, @platform
    end

    entities.map { |e| @em.unit_of_work.manage_entity e }
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
      str << " FROM " << table_name << ' ' << table_alias << @current_persister_context.select_join_sql

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
    columns = self.select_condition_statement_column_sql field

    # TODO: Support comparison type

    columns.join " AND " do |column_name|
      if value.is_a? Array
        in_sql = "#{column_name} IN (#{value.size.times.join ", " { '?' }})"

        if value.includes? nil
          next "(#{in_sql} OR #{column_name} IS NULL)"
        end

        next in_sql
      end

      if value.nil?
        next "#{column_name} IS NULL"
      end

      "#{column_name} = ?"
    end
  end

  def select_condition_statement_column_sql(field : String) : Array(String)
    property = @class_metadata.property(field).not_nil!

    if property.is_a? AORM::Mapping::FieldMetadata
      table_alias = sql_table_alias property.table_name
      column_name = @platform.quote_identifier property.column_name

      return ["#{table_alias}.#{column_name}"]
    end

    if property.is_a? AORM::Mapping::AssociationMetadata
      owning_association = property

      raise "Inverse side usage" unless owning_association.is_owning_side?

      table_alias = self.sql_table_alias @class_metadata.table_name

      return owning_association.join_columns.map do |join_column|
        quoted_column_name = @platform.quote_identifier join_column.column_name

        "#{table_alias}.#{quoted_column_name}"
      end
    end

    # TODO: Handle this better
    raise "Unknown field"
  end

  protected def select_columns_sql : String
    if col_list = @current_persister_context.select_column_list
      return col_list
    end

    @current_persister_context.select_join_sql = ""

    column_list = [] of String
    eager_alias_counter = 0

    @class_metadata.each do |property|
      case property
      when AORM::Mapping::FieldMetadata then column_list << self.select_column_sql property
      when AORM::Mapping::AssociationMetadata
        assoc_column_sql = self.select_column_asssociation_sql property.name, property, @class_metadata

        column_list << assoc_column_sql unless assoc_column_sql.empty?

        # TOOD: Handle non ToOne associations
        # TOOD: Change this back to ToOneAssociationMetadata
        is_assoc_to_one_inverse_side = !property.is_owning_side?
        is_assoc_from_one_eager = true && property.fetch_mode.eager?

        next if !(is_assoc_to_one_inverse_side || is_assoc_from_one_eager)

        target_entity = property.target_entity
        eager_class_metadata = @em.class_metadata target_entity

        assoc_alias = "e#{eager_alias_counter}"
        eager_alias_counter += 1

        eager_class_metadata.each do |eager_property|
          case eager_property
          when AORM::Mapping::FieldMetadata then column_list << self.select_column_sql eager_property, assoc_alias
          when AORM::Mapping::OneToOneAssociationMetadata
            # TODO: Could probably use overloads for this
            column_list << self.select_column_asssociation_sql(
              eager_property.name,
              eager_property,
              eager_class_metadata,
              assoc_alias
            )
          end
        end

        # TODO: Handle non ToOne associations
        owning_association = property
        join_condition = [] of String

        unless property.is_owning_side?
          owning_association = eager_class_metadata.property property.mapped_by.not_nil!
        end

        owning_association = owning_association.as AORM::Mapping::AssociationMetadata

        join_table_alias = self.sql_table_alias eager_class_metadata.table_name, assoc_alias
        join_table_name = eager_class_metadata.table.quoted_qualified_name @platform

        @current_persister_context.select_join_sql += " #{self.join_sql_for_association property}"

        source_class_metadata = @em.class_metadata owning_association.source_entity
        target_class_metadata = @em.class_metadata owning_association.target_entity

        target_table_alias = self.sql_table_alias target_class_metadata.table_name, property.is_owning_side? ? assoc_alias : ""
        source_table_alias = self.sql_table_alias source_class_metadata.table_name, property.is_owning_side? ? "" : assoc_alias

        owning_association.join_columns.each do |join_column|
          join_condition << "#{source_table_alias}.#{@platform.quote_identifier join_column.column_name} = #{target_table_alias}.#{@platform.quote_identifier join_column.referenced_column_name}"
        end

        # TODO: Handle filter SQL

        @current_persister_context.select_join_sql += %( #{join_table_name} #{join_table_alias} ON #{join_condition.join ", "})
      end
    end

    @current_persister_context.select_column_list = column_list.join ", "
  end

  protected def select_column_sql(property : AORM::Mapping::ColumnMetadata, calias : String = "r") : String
    column_alias = self.sql_column_alias

    sql = %(#{self.sql_table_alias property.table_name, (calias == "r" ? "" : calias)}.#{@platform.quote_identifier property.column_name})

    # TODO: Support the type altering the sql
    "#{sql} AS #{column_alias}"
  end

  protected def select_column_asssociation_sql(column_name : String, association : AORM::Mapping::AssociationMetadata, class_metadata : AORM::Mapping::ClassBase, calias : String = "r") : String
    # TODO: Handle non ToOne associations
    return "" unless association.is_owning_side?

    target_class_metadata = @em.class_metadata association.target_entity
    table_alias = self.sql_table_alias class_metadata.table_name, (calias == "r" ? "" : calias)

    association.join_columns.each.join ", " do |join_column|
      column_name = join_column.column_name
      quoted_column_name = @platform.quote_identifier column_name
      result_column_name = self.sql_column_alias

      "#{table_alias}.#{quoted_column_name} AS #{result_column_name}"
    end
  end

  protected def join_sql_for_association(association_metadata : AORM::Mapping::AssociationMetadata) : String
    return "LEFT JOIN" unless association_metadata.is_owning_side?

    association_metadata.join_columns.each do |join_column|
      next unless join_column.nilable?

      return "LEFT JOIN"
    end

    "INNER JOIN"
  end

  def count(criteria : Hash(String, _)) : Int
    sql = @platform.modify_sql_placeholders self.count_sql criteria
    params = self.expand_parameters criteria

    stmt = @connection.fetch_or_build_prepared_statement sql

    stmt.scalar(args: params).as Int
  end

  def count_sql(criteria : Hash(String, _)) : String
    table_name = @class_metadata.table.quoted_qualified_name @platform
    table_alias = self.sql_table_alias @class_metadata.table_name

    conditional_sql = self.select_conditional_sql criteria

    String.build do |str|
      str << "SELECT COUNT(*)"
      str << " FROM #{table_name} #{table_alias}"

      unless conditional_sql.empty?
        str << " WHERE " << conditional_sql
      end
    end
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

    update_data.each do |param|
      set << "#{@platform.quote_identifier param.name} = ?"
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

    sql = @platform.modify_sql_placeholders %(UPDATE #{quoted_table_name} SET #{set.join ", "} WHERE #{where.join " = ? AND "} = ?)

    stmt = @connection.fetch_or_build_prepared_statement sql

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

    id = Hash(String, AORM::Mapping::Value).new

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

    id.each do |name, value|
      v = value.value

      if v.nil?
        conditions << @platform.is_null_expression name
        next
      end

      columns << name
      values << v
      conditions << "#{name} = ?"
    end

    stmt = @connection.fetch_or_build_prepared_statement @platform.modify_sql_placeholders %(DELETE FROM #{table_name} WHERE #{conditions.join(" AND ")})

    !stmt.exec(args: values).rows_affected.zero?
  end

  def insert(entity : AORM::Entity) : Nil
    stmt = @connection.fetch_or_build_prepared_statement @platform.modify_sql_placeholders self.insert_sql
    insert_data = self.prepare_insert_data entity

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

    columns.each do |_name, metadata|
      quoted_columns << @platform.quote_identifier metadata.column_name
      values << metadata.type.to_database_value_sql "?", @platform
    end

    @insert_sql = %(INSERT INTO #{table_name} (#{quoted_columns.join ", "}) VALUES (#{values.join ", "}))
  end

  protected def prepare_insert_data(entity : AORM::Entity) : Array
    @class_metadata.map do |property|
      property.get_value(entity).value
    end
  end

  protected def insert_column_list : Hash(String, AORM::Mapping::ColumnMetadata)
    if columns = @insert_columns
      return columns
    end

    @insert_columns = self.column_list(@class_metadata)
  end

  protected def column_list(class_metadata : AORM::Mapping::ClassBase, column_prefix : String = "") : Hash(String, AORM::Mapping::ColumnMetadata)
    columns = Hash(String, AORM::Mapping::ColumnMetadata).new

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
