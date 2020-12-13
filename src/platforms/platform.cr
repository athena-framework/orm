abstract class Athena::ORM::Platforms::Platform
  # GENERAL CONFIGURATION

  # getter keyword_list : AORM::Platforms::Keywords::List { self.reserved_keywords_class.new }

  abstract def name : String
  # abstract def reserved_keywords_class : AORM::Platforms::Keywords::List.class

  # TYPES
  # TODO: Have some struct to represent metadata included in the `AORMA::Column` annotation and pass that to these type methods.

  abstract def boolean_type_declaration_sql : String
  abstract def integer_type_declaration_sql : String
  abstract def big_int_type_declaration_sql : String
  abstract def small_int_type_declaration_sql : String

  abstract def sequence_next_val_sql(sequence_name : String) : String

  def varchar_type_declaration_sql : String
    ""
  end

  def guid_type_declaration_sql : String
    ""
  end

  def float_type_declaration_sql : String
    "DOUBLE PRECISION"
  end

  # EXPRESSIONS

  def is_null_expression(expression : String) : String
    "#{expression} IS NULL"
  end

  def is_not_null_expression(expression : String) : String
    "#{expression} IS NOT NULL"
  end

  # IDENTIFIERS

  def identifier_quote_character : Char
    '"'
  end

  def string_literal_quote_character : Char
    '\''
  end

  def quote_identifier(identifier : String) : String
    # TODO: Handle . separated identifier chains

    self.quote_single_identifier identifier
  end

  def quote_single_identifier(identifier : String) : String
    quote_char = self.identifier_quote_character

    %(#{quote_char}#{identifier.gsub(quote_char, "#{quote_char}#{quote_char}")}#{quote_char})
  end

  def sql_result_casing(column : String) : String
    column
  end

  # Platforms can override this to convert the default `?` placeholders
  # to platoform specific placeholders.
  def modify_sql_placeholders(sql : String) : String
    sql
  end

  def modify_limit_query(sql : String, limit : Int?, offset : Int?) : String
    if offset && offset < 0
      raise ArgumentError.new "Offset cannot be negative"
    end

    if offset && offset > 0 && !self.supports_limit_offset?
      raise "Platform does not support offset values in limit queries"
    end

    self.do_modify_limit_query sql, limit, offset
  end

  def sequence_prefix(table_name : String, schema_name : String? = nil) : String
    return table_name if schema_name.nil?

    !self.supports_schemas? && self.can_emulate_schemas? ? "#{schema_name}__#{table_name}" : "#{schema_name}.#{table_name}"
  end

  def fix_schema_element_name(name : String) : String
    name
  end

  protected def modify_limit_query(sql : String, limit : Int?, offset : Int?) : String
    sql += " LIMIT #{limit}" if limit
    sql += " OFFSET #{offset}" if offset && offset > 0

    sql
  end

  # LENGTHS

  def char_max_length : Int32
    self.varchar_max_length
  end

  def varchar_max_length : Int32
    5000
  end

  def varchar_default_length : Int32
    255
  end

  def max_identifier_length : Int32
    63
  end

  # FEATURE SUPPORT

  def can_emulate_schemas? : Bool
    false
  end

  def prefers_identity_columns? : Bool
    false
  end

  def prefers_sequences? : Bool
    false
  end

  def supports_limit_offset? : Bool
    true
  end

  def supports_schemas? : Bool
    false
  end

  def uses_sequence_emulated_identity_columns? : Bool
    false
  end
end
