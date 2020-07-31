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

  def identifier(entity : AORM::Entity) : Array(AORM::Metadata::Identifier)
    @class_metadata.identifier.compact_map do |field_name|
      property = @class_metadata.property(field_name).not_nil!
      value = property.get_value entity

      unless value.nil?
        AORM::Metadata::ColumnIdentifier.new(field_name, value).as AORM::Metadata::Identifier
      end
    end
  end

  def insert(entity : AORM::Entity) : Nil
    insert_sql = self.insert_sql

    stmt = @connection.fetch_or_build_prepared_statement insert_sql
    table_name = @class_metadata.table_name
    insert_data = self.prepare_insert_data entity

    puts insert_sql
    puts table_name
    puts insert_data

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
      property.get_value entity
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
