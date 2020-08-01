struct Athena::ORM::BasicEntityPersister
  include Athena::ORM::EntityPersisterInterface

  @connection : DB::Connection
  @platform : AORM::Platforms::Platform

  @insert_sql : String? = nil
  @insert_columns : Hash(String, AORM::Metadata::ColumnBase)? = nil

  def initialize(@em : AORM::EntityManagerInterface, @class_metadata : AORM::Metadata::Class)
    @connection = @em.connection
    @platform = @connection.database_platform
  end

  def identifier(entity : AORM::Entity) : Array(AORM::Metadata::Value)
    @class_metadata.identifier.compact_map do |field_name|
      property = @class_metadata.property(field_name).not_nil!
      property.get_value(entity) do |column_value|
        column_value.as AORM::Metadata::Value
      end
    end
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

    stmt = @connection.fetch_or_build_prepared_statement delete_sql

    !stmt.exec(args: values).rows_affected.zero?
  end

  def insert(entity : AORM::Entity) : Nil
    stmt = @connection.fetch_or_build_prepared_statement self.insert_sql
    table_name = @class_metadata.table_name
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
      property.get_value(entity) do |column_value|
        column_value.value
      end
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
end
