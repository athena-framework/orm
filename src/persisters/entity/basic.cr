require "./interface"

class Athena::ORM::Persisters::Entity::Basic
  include Athena::ORM::Persisters::Entity::Interface

  COMPARISON_MAP = {
    "="   => "= %s",
    "<>"  => "!= %s",
    ">"   => "> %s",
    ">="  => ">= %s",
    "<"   => "< %s",
    "<="  => "<= %s",
    "IN"  => "IN (%s)",
    "NIN" => "NOT IN (%s)",
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
    hints : Query::Hints = Query::Hints.new,
    lock_mode : LockMode? = nil,
    limit : Int? = nil,
    order_by : Hash(String, String)? = nil,
  ) : AORM::Entity?
    self.switch_persister_context nil, limit
    sql = self.select_sql criteria, association, lock_mode, limit, nil, order_by
    params = self.expand_parameters criteria

    hydrator = @em.hydrator(!@current_persister_context.select_join_sql.empty? ? AORM::HydrationMode::Object : AORM::HydrationMode::SimpleObject)

    entities = [] of AORM::Entity

    @connection.query sql, args: params do |rs|
      entities = hydrator.hydrate_all(rs, @current_persister_context.rsm, hints)
    end

    entities.first?
  end

  def load_all(
    criteria : Hash(String, _) = Hash(String, DB::Any).new,
    order_by : Hash(String, String)? = nil,
    limit : Int? = nil,
    offset : Int32? = nil,
  ) : Array(AORM::Entity)
    self.switch_persister_context offset, limit
    sql = self.select_sql criteria, nil, nil, limit, offset, order_by
    params = self.expand_parameters criteria

    hints = Query::Hints.new defer_eager_load: true

    hydrator = @em.hydrator(!@current_persister_context.select_join_sql.empty? ? AORM::HydrationMode::Object : AORM::HydrationMode::SimpleObject)

    entities = [] of AORM::Entity

    @connection.query sql, args: params do |rs|
      entities = hydrator.hydrate_all(rs, @current_persister_context.rsm, hints)
    end

    entities
  end

  def count(criteria : Hash(String, _) = Hash(String, DB::Any).new) : Int32
    sql = self.count_sql criteria
    params = self.expand_parameters criteria

    # COUNT(*) is by definition a single scalar value; `scalar` reads exactly
    # that without round-tripping through a result-set cursor. Drivers report
    # the count as `Int64`; narrow at the boundary.
    @connection.scalar(sql, args: params).as(Int64).to_i32
  end

  # Builds the `SELECT COUNT(*) FROM ... [WHERE ...]` SQL for the given
  # criteria. Mirrors Doctrine's `BasicEntityPersister::getCountSQL`.
  def count_sql(criteria : Hash(String, _)) : String
    quoted_table = @quote_strategy.table_name @class_metadata, @platform
    table_alias = self.sql_table_alias @class_metadata.entity_class

    condition_sql = criteria.empty? ? "" : self.select_condition_sql(criteria)

    # TODO: Append filter SQL once filter integration lands.

    String.build do |io|
      io << "SELECT COUNT(*) FROM " << quoted_table << " " << table_alias
      unless condition_sql.empty?
        io << " WHERE " << condition_sql
      end
    end
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

    params = self.expand_parameters criteria

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

      # Unwrap at the DB-binding boundary.
      statement.exec args: insert_data[table_name].values.map(&.value.as(DB::Any))

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

  def expand_parameters(criteria : Hash(String, _)) : Array
    criteria.values.flat_map do |v|
      next [] of NoReturn if v.nil?

      if v.is_a?(Indexable)
        # IN clause: bind each non-null element as its own parameter.
        v.to_a.compact.flat_map { |item| PersisterHelper.convert_to_parameter_value(item, @em) }
      else
        PersisterHelper.convert_to_parameter_value(v, @em)
      end
    end
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
    update_data : Hash(String, Mapping::Value),
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

      # Unwrap at the DB-binding boundary: callers store wrapped values in the
      # changeset path, but `connection.exec`'s args slot wants raw `DB::Any`.
      params << value.value.as(DB::Any)
      set << "#{column} = #{placeholder}"
    end

    where = [] of String
    identifier = @em.unit_of_work.entity_identifier entity

    @class_metadata.identifier.each do |id_field|
      unless assoc = @class_metadata.association_mappings[id_field]?
        id_value = identifier[id_field].value

        if id_value.is_a?(DB::Any)
          params << id_value
        elsif id_value.is_a?(AORM::Entity)
          raise "BUG: non-association AORM::Entity value"
        elsif id_value.is_a?(Collection)
          raise "BUG: collection cannot be identifier"
        end

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

  private def delete_condition_sql(criteria : Hash(String, Mapping::Value))
    values = [] of DB::Any
    conditions = [] of String

    criteria.each do |k, wrapped|
      value = wrapped.value

      if value.nil?
        conditions << "#{k} IS NULL"

        next
      end

      if value.is_a? AORM::Entity
        raise "BUG: non-association AORM::Entity value"
      end

      if value.is_a? Collection
        raise "BUG: collection in delete condition"
      end

      if value.is_a?(DB::Any)
        values << value
        conditions << "#{k} = ?"
      end
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

  protected def prepare_insert_data(entity : AORM::Entity) : Hash(String, Hash(String, Mapping::Value))
    self.prepare_update_data entity, true
  end

  protected def prepare_update_data(entity : AORM::Entity, is_insert : Bool = false) : Hash(String, Hash(String, Mapping::Value))
    uow = @em.unit_of_work
    result = Hash(String, Hash(String, Mapping::Value)).new do |hash, key|
      hash[key] = Hash(String, Mapping::Value).new
    end

    # TODO: Handle versioning

    uow.entity_changeset(entity).each do |field, change|
      # TODO: Handle versioning
      # TODO: Handle embedded classes

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

        raw = change.new.value
        if raw.is_a?(DB::Any)
          result[self.owning_table field][column_name] = change.new
        elsif raw.is_a?(AORM::Entity)
          raise "BUG: non-association AORM::Entity value"
        end

        next
      end

      # Only owning side of x-1 associations can have a FK column.
      next unless assoc.is_a? Mapping::ToOneOwningSide

      new_value = change.new.value

      # An associated entity that's still queued for insert hasn't received its
      # identifier yet — null the FK column out for the current INSERT and
      # schedule an extra UPDATE to patch the column once the target has an id.
      # The topological sort handles the non-cyclic case before we get here, so
      # this branch only fires on true cycles.
      if new_value.is_a?(AORM::Entity) && uow.is_scheduled_for_insert?(new_value)
        patch = Hash(String, UnitOfWork::Change).new
        patch[field] = change
        uow.schedule_extra_update entity, patch
        new_value = nil
      end

      new_value_id = nil
      if new_value.is_a?(AORM::Entity)
        new_value_id = uow.entity_identifier(new_value)
      end

      target_class = @em.class_metadata(assoc.target_entity)
      owning_table = self.owning_table(field)

      assoc.join_columns.each do |join_column|
        source_column = join_column.name
        target_column = join_column.referenced_column_name

        @column_types[source_column] = PersisterHelper.type_of_column(target_column, target_class, @em)

        column_value = if new_value_id && (target_field = target_class.field_names[target_column]?)
                         new_value_id[target_field]
                       else
                         Mapping::SingleValue(DB::Any).new(nil)
                       end

        result[owning_table][source_column] = column_value.as Mapping::Value
      end
    end

    result
  end

  protected def select_sql(
    criteria : Hash(String, _), # TODO: Handle `Criteria` obj
    association : Mapping::Association? = nil,
    lock_mode : LockMode? = nil,
    limit : Int? = nil,
    offset : Int32? = nil,
    order_by : Hash(String, String)? = nil,
  ) : String
    self.switch_persister_context offset, limit

    join_sql = ""
    order_by_sql = ""

    if association.is_a?(Mapping::ManyToMany)
      join_sql = self.select_many_to_many_join_sql association
    end

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
      # TODO: Handle OrderBy
    end

    @platform.modify_limit_query query, limit, offset || 0 # TODO: Append lock SQL
  end

  protected def select_many_to_many_join_sql(many_to_many : Mapping::ManyToMany) : String
    conditions = [] of String
    source_table_alias = self.sql_table_alias @class_metadata.entity_class

    association = @em.metadata_factory.owning_side(many_to_many).as Mapping::ManyToManyOwningSide
    join_table_name = @quote_strategy.join_table_name association, @class_metadata, @platform

    raise "BUG: Nil JoinTable" unless join_table = association.join_table
    join_columns = association.is_a?(Mapping::OwningSide) ? join_table.inverse_join_columns : join_table.join_columns

    join_columns.each do |join_column|
      quoted_source_column = @quote_strategy.join_column_name join_column, @class_metadata, @platform
      quoted_target_column = @quote_strategy.referenced_join_column_name join_column, @class_metadata, @platform
      conditions << "#{source_table_alias}.#{quoted_target_column} = #{join_table_name}.#{quoted_source_column}"
    end

    " INNER JOIN #{join_table_name} ON #{conditions.join " AND "}"
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
    @current_persister_context.rsm.add_entity_result @class_metadata.entity_class, "r"

    # Add regular columns
    @class_metadata.field_names.each_value do |field|
      column_list << self.select_column_sql field, @class_metadata
    end

    @current_persister_context.select_join_sql = ""

    # Add ToOne owning-side FK columns as RSM meta results so the hydrator can
    # surface them in row data for `UnitOfWork#create_entity` to resolve.
    @class_metadata.association_mappings.each do |assoc_field, assoc|
      assoc_column_sql = self.select_column_association_sql assoc_field, assoc, @class_metadata
      column_list << assoc_column_sql unless assoc_column_sql.empty?
    end

    sql = @current_persister_context.select_column_list_sql = column_list.join ", "
    # TODO: Update filter hash

    sql
  end

  # Emits the FK column SQL for a ToOne owning-side association, registering each join column as a meta result on the RSM.
  # Returns an empty string for any other association shape.
  protected def select_column_association_sql(
    field : String,
    assoc : Mapping::Association,
    metadata : Mapping::ClassInterface,
    col_alias : String = "r",
  ) : String
    return "" unless assoc.is_a?(Mapping::ToOneOwningSide)

    target_class = @em.class_metadata assoc.target_entity
    is_identifier = assoc.id? == true
    table_alias_root = col_alias == "r" ? "" : col_alias
    table_alias = self.sql_table_alias metadata.entity_class, table_alias_root

    columns = [] of String
    assoc.join_columns.each do |jc|
      quoted_column = @quote_strategy.join_column_name jc, metadata, @platform
      result_column_alias = self.sql_column_alias jc.name
      type = PersisterHelper.type_of_column jc.referenced_column_name, target_class, @em

      @current_persister_context.rsm.add_meta_result col_alias, result_column_alias, jc.name, is_identifier, type

      columns << "#{table_alias}.#{quoted_column} AS #{result_column_alias}"
    end

    columns.join ", "
  end

  def select_condition_statement_sql(field : String, value : _, association : Mapping::Association? = nil, comparison : String? = nil) : String
    value = value.is_a?(Mapping::Value) ? value.value : value
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

      if comparison == "IN" || comparison == "NIN"
        elements = value.is_a?(Indexable) ? value.to_a : [value]

        if elements.empty?
          selected_columns << "1=0"
          next
        end

        null_count = elements.count(&.nil?)
        non_null_count = elements.size - null_count

        if non_null_count.zero?
          selected_columns << "#{column} IS NULL"
          next
        end

        placeholders = Array.new(non_null_count, placeholder).join ", "
        in_clause = "#{column} #{sprintf COMPARISON_MAP[comparison], placeholders}"

        selected_columns << (null_count > 0 ? "(#{in_clause} OR #{column} IS NULL)" : in_clause)
        next
      end

      selected_columns << "#{column} #{sprintf COMPARISON_MAP[comparison], placeholder}"
    end

    selected_columns.join " AND "
  end

  # Builds the ORDER BY fragment for the entity persister's SELECT.
  #
  # Each entry in *order_by* maps a field (or ToOne owning-side association)
  # name to an orientation string (`"ASC"` or `"DESC"`, case-insensitive).
  # Field names resolve to entity column names via `field_mappings`;
  # association names expand to one ORDER BY clause per join column. Other
  # shapes raise.
  #
  # Returns either an empty string (no input) or a leading-space-prefixed
  # `" ORDER BY ..."` fragment ready to splice into the SELECT.
  protected def order_by_sql(order_by : Hash(String, String), base_table_alias : String) : String
    return "" if order_by.empty?

    parts = [] of String

    order_by.each do |field, orientation|
      orientation = orientation.strip.upcase

      unless orientation.in?({"ASC", "DESC"})
        raise "Invalid ORDER BY orientation '#{orientation}' for field '#{field}' on '#{@class_metadata.entity_class}'"
      end

      if @class_metadata.field_mappings.has_key? field
        # TODO: Resolve inherited fields to their declaring class's table alias.
        column = @quote_strategy.column_name field, @class_metadata, @platform
        parts << "#{base_table_alias}.#{column} #{orientation}"
        next
      end

      if assoc = @class_metadata.association_mappings[field]?
        unless assoc.is_a?(Mapping::OwningSide) && assoc.is_a?(Mapping::ToOne)
          raise "Cannot order by inverse side of association '#{field}' on '#{@class_metadata.entity_class}'. Use the owning side."
        end

        # TODO: Resolve inherited associations to their declaring class's table alias.
        assoc.join_columns.each do |jc|
          column = @quote_strategy.join_column_name jc, @class_metadata, @platform
          parts << "#{base_table_alias}.#{column} #{orientation}"
        end

        next
      end

      raise "Unrecognized field '#{field}' on '#{@class_metadata.entity_class}'"
    end

    " ORDER BY #{parts.join(", ")}"
  end

  protected def select_column_sql(field : String, metadata : Mapping::ClassInterface, col_alias : String = "r") : String
    root = col_alias == "r" ? "" : col_alias
    table_alias = self.sql_table_alias metadata.entity_class, root
    fm = metadata.field_mappings[field]
    sql = "#{table_alias}.#{@quote_strategy.column_name field, metadata, @platform}"

    rsm = @current_persister_context.rsm

    # Check if RSM already has an alias for this field (from a previous generation)
    column_alias = rsm.field_mappings.key_for?(field).try do |col|
      col if rsm.column_owner_map[col]? == col_alias
    end

    unless column_alias
      column_alias = self.sql_column_alias fm.column_name
    end

    rsm.add_field_result col_alias, column_alias, field

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
    if @class_metadata.field_mappings.has_key? field
      # TODO: Handle inherited fields
      entity_class = @class_metadata.entity_class

      return [
        "#{self.sql_table_alias(entity_class)}.#{@quote_strategy.column_name field, @class_metadata, @platform}",
      ]
    end

    if assoc = @class_metadata.association_mappings[field]?
      columns = [] of String

      if assoc.is_a? Mapping::ManyToMany
        # TODO: handle ManyToMany branch
        # Needs join-table column lookup using the outer `association` context.
        raise "TODO: ManyToMany association criteria"
      else
        unless assoc.is_a?(Mapping::OwningSide) && assoc.is_a?(Mapping::ToOne)
          raise "Cannot match on inverse side of association '#{field}' on '#{@class_metadata.entity_class}'. Use the owning side."
        end

        # TODO: Handle inherited associations
        entity_class = @class_metadata.entity_class
        table_alias = self.sql_table_alias entity_class

        assoc.join_columns.each do |jc|
          columns << "#{table_alias}.#{@quote_strategy.join_column_name jc, @class_metadata, @platform}"
        end
      end

      return columns
    end

    if association && !field.includes?(' ') && !field.includes?('(')
      return [field]
    end

    raise "unrecognized field"
  end

  private def switch_persister_context(offset : Int?, limit : Int?) : Nil
    if offset.nil? && limit.nil?
      @current_persister_context = @no_limits_context

      return
    end

    @current_persister_context = @limits_handling_context
  end

  private def load_collection_from_result_set(
    assoc : Mapping::Association,
    rs : DB::ResultSet,
    collection : AORM::PersistentCollection,
  ) : Array
    hints = Query::Hints.new(
      defer_eager_load: true,
      collection: collection
    )

    # TODO: Handle indexed association

    @em.hydrator(:object).hydrate_all(rs, @current_persister_context.rsm, hints).as Array(AORM::Entity)
  end

  def load_many_to_many_collection(
    assoc : Mapping::ManyToMany,
    source_entity : AORM::Entity,
    collection : AORM::PersistentCollection,
  ) : Array
    rs = self.many_to_many_statement assoc, source_entity

    self.load_collection_from_result_set assoc, rs, collection
  end

  def load_one_to_many_collection(
    assoc : Mapping::OneToMany,
    source_entity : AORM::Entity,
    collection : AORM::PersistentCollection,
  ) : Array
    rs = self.one_to_many_statement assoc, source_entity

    self.load_collection_from_result_set assoc, rs, collection
  end

  # Loads the target of a ToOne *inverse-side* association — the OWNING-side entity whose FK column points at *source_entity*.
  # Always eager: ToOne inverse sides have no proxy semantics.
  #
  # `self` is the persister for the *target* class (the owning-side entity);
  # `assoc.mapped_by` names the owning-side association on that class.
  def load_one_to_one_entity(
    assoc : Mapping::ToOneInverseSide,
    source_entity : AORM::Entity,
  ) : AORM::Entity?
    owning_assoc = @class_metadata.association_mappings[assoc.mapped_by]?
    raise "BUG: ToOne inverse side '#{assoc.mapped_by}' not found on '#{@class_metadata.entity_class}'" unless owning_assoc.is_a?(Mapping::ToOneOwningSide)

    # Filter the owning entity's table by its FK association field.
    # The persister's WHERE expansion converts an entity value here into `<owning_table>.<fk_col> = <source_pk>`
    criteria = {assoc.mapped_by => source_entity}

    self.load criteria, nil, owning_assoc
  end

  private def one_to_many_statement(
    assoc : Mapping::OneToMany,
    source_entity : AORM::Entity,
    offset : Int32? = nil,
    limit : Int32? = nil,
  ) : ::DB::ResultSet
    self.switch_persister_context offset, limit

    # `self` is the persister for the target ("many") class.
    # The owning side of the relationship lives on the target as a `ManyToOneOwningSide`, named by the inverse side's `mapped_by`.
    source_class_metadata = @em.class_metadata assoc.source_entity
    owning_assoc = @class_metadata.association_mappings[assoc.mapped_by]?
    raise "BUG: OneToMany owning side '#{assoc.mapped_by}' not found on '#{@class_metadata.entity_class}'" unless owning_assoc.is_a?(Mapping::ManyToOneOwningSide)

    table_alias = self.sql_table_alias @class_metadata.entity_class
    criteria = Hash(String, Mapping::Value).new
    parameters = [] of CollectionParameter

    owning_assoc.source_to_target_key_columns.each do |target_fk_column, source_pk_column|
      field_name = source_class_metadata.field_names[source_pk_column]?
      raise "BUG: source PK column '#{source_pk_column}' has no mapped field on '#{source_class_metadata.entity_class}'" unless field_name

      fi = source_class_metadata.field_info[field_name]
      value = fi.create_column_value fi.get_value source_entity

      quoted_target_column = @quote_strategy.column_name field_name, source_class_metadata, @platform
      criteria["#{table_alias}.#{target_fk_column}"] = value
      parameters << CollectionParameter.new value, source_class_metadata
    end

    sql = self.select_sql criteria, assoc, nil, limit, offset
    params = self.expand_to_many_parameters parameters

    @connection.query sql, args: params
  end

  record CollectionParameter, value : Mapping::Value, source_class_metadata : Mapping::ClassInterface

  private def many_to_many_statement(
    assoc : Mapping::ManyToMany,
    source_entity : AORM::Entity,
    offset : Int32? = nil,
    limit : Int32? = nil,
  ) : ::DB::ResultSet
    self.switch_persister_context offset, limit

    source_class_metadata = @em.class_metadata(assoc.source_entity)

    class_metadata = source_class_metadata
    criteria = Hash(String, Mapping::Value).new
    parameters = [] of CollectionParameter

    unless assoc.is_a? Mapping::OwningSide
      class_metadata = @em.class_metadata assoc.target_entity
    end

    association = @em.metadata_factory.owning_side(assoc).as Mapping::ManyToManyOwningSide
    raise "BUG: Nil JoinTable" unless join_table = association.join_table

    join_columns = assoc.is_a?(Mapping::OwningSide) ? join_table.join_columns : join_table.inverse_join_columns

    quoted_join_table = @quote_strategy.join_table_name association, class_metadata, @platform

    join_columns.each do |join_column|
      source_key_column = join_column.referenced_column_name
      quoted_key_column = @quote_strategy.join_column_name join_column, class_metadata, @platform

      # TODO: Handle foreign identifiers

      value = if field_name = source_class_metadata.field_names[source_key_column]?
                fi = source_class_metadata.field_info[field_name]
                fi.create_column_value fi.get_value source_entity
              else
                raise "Join column doesn't point to mapped field"
              end

      criteria["#{quoted_join_table}.#{quoted_key_column}"] = value
      parameters << CollectionParameter.new value, source_class_metadata
    end

    sql = self.select_sql criteria, assoc, nil, limit, offset

    # TODO: Do we need to return types?
    params = self.expand_to_many_parameters parameters

    @connection.query sql, args: params
  end

  private def expand_to_many_parameters(parameters : Array(CollectionParameter)) : Array
    parameters.flat_map do |param|
      value = param.value
      value = value.is_a?(Mapping::Value) ? value.value : value

      next if value.nil?

      PersisterHelper.convert_to_parameter_value value, @em
    end
  end
end
