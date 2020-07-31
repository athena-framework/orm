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

  def insert(entity : AORM::Entity) : Nil
    pp @connection
    pp @platform

    # stmt = @connection.prepare self.insert_sql
    stmt = self.insert_sql

    puts stmt
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

    columns.each do |name, metadata|
      quoted_columns << @platform.quote_identifier metadata.column_name
      values << metadata.type.to_database_value_sql "?", @platform
    end

    quoted_columns = quoted_columns.join(", ")
    values = values.join(", ")

    @insert_sql = "INSERT INTO #{table_name} (#{quoted_columns}) (#{values})"
  end

  protected def insert_column_list : Hash(String, AORM::Metadata::ColumnBase)
    if columns = @insert_columns
      return columns
    end

    @insert_columns = self.column_list(@class_metadata)
  end

  protected def column_list(class_metadata : AORM::Metadata::Class, column_prefix : String = "") : Hash(String, AORM::Metadata::ColumnBase)
    columns = Hash(String, AORM::Metadata::ColumnBase).new

    class_metadata.each_property do |name, property|
      columns["#{column_prefix}#{name}"] = property
    end

    columns
  end
end
