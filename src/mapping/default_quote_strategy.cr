require "./quote_strategy_interface"

struct Athena::ORM::Mapping::DefaultQuoteStrategy
  include Athena::ORM::Mapping::QuoteStrategyInterface

  def table_name(metadata : Mapping::ClassInterface, platform : Platforms::Platform) : String
    table_name = metadata.table.name.not_nil!

    # TODO: Handle schema

    metadata.table.quoted ? platform.quote_single_identifier(table_name) : table_name
  end

  def column_name(field_name : String, metadata : Mapping::ClassInterface, platform : Platforms::Platform) : String
    fm = metadata.field_mappings[field_name]

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
