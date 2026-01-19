require "./quote_strategy_interface"

struct Athena::ORM::Mapping::DefaultQuoteStrategy
  include Athena::ORM::Mapping::QuoteStrategyInterface

  def identifier_column_names(class_metadata : Mapping::ClassInterface, platform : Platforms::Platform) : Array(String)
    quoted_column_names = [] of String

    class_metadata.identifier.each do |field_name|
      if class_metadata.field_mappings.has_key?(field_name)
        quoted_column_names << self.column_name field_name, class_metadata, platform

        next
      end

      # TODO: Handle associations
    end

    quoted_column_names
  end

  def table_name(class_metadata : Mapping::ClassInterface, platform : Platforms::Platform) : String
    table_name = class_metadata.table.name.not_nil!

    # TODO: Handle schema

    class_metadata.table.quoted ? platform.quote_single_identifier(table_name) : table_name
  end

  def join_table_name(association : Mapping::ManyToManyOwningSide, class_metadata : Mapping::ClassInterface, platform : Platforms::Platform) : String
    # TODO: Handle schema
    join_table = association.join_table.not_nil!

    schema = ""

    if sch = join_table.schema.presence
      schema = sch
    end

    table_name = join_table.name

    if join_table.quoted?
      table_name = platform.quote_single_identifier table_name
    end

    "#{schema}#{table_name}"
  end

  def referenced_join_column_name(join_column : Mapping::JoinColumn, class_metadata : Mapping::ClassInterface, platform : Platforms::Platform) : String
    join_column.quoted ? platform.quote_single_identifier(join_column.referenced_column_name) : join_column.referenced_column_name
  end

  def join_column_name(join_column : Mapping::JoinColumn, class_metadata : Mapping::ClassInterface, platform : Platforms::Platform) : String
    join_column.quoted ? platform.quote_single_identifier(join_column.name) : join_column.name
  end

  def column_name(field_name : String, class_metadata : Mapping::ClassInterface, platform : Platforms::Platform) : String
    fm = class_metadata.field_mappings[field_name]

    fm.quoted ? platform.quote_single_identifier(fm.column_name) : fm.column_name
  end

  def column_alias(column_name : String, counter : Int, platform : Platforms::Platform, class_metadata : Mapping::ClassInterface? = nil) : String
    # 1. Concat name and counter
    # 2. Trim alias to max length allowed by platform, trimming from beginning if needed
    # 3. Strip non alphanumeric characters
    # 4. Prefix with `_` if numeric
    column_name = "#{column_name}_#{counter}"
    column_name = column_name[-{platform.max_identifier_length, column_name.size}.min..]
    column_name = column_name.gsub /[^A-Za-z0-9_]/, ""
    column_name = column_name.to_i? ? "_#{column_name}" : column_name

    self.sql_result_casing platform, column_name
  end
end
