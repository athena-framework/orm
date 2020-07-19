abstract struct Athena::ORM::Platforms::Platform
  abstract def name : String

  abstract def boolean_type_declaration_sql : String
  abstract def integer_type_declaration_sql : String
  abstract def big_int_type_declaration_sql : String
  abstract def small_int_type_declaration_sql : String

  def varchar_type_declaration_sql : String
    ""
  end

  def guid_type_declaration_sql : String
    ""
  end

  def float_type_declaration_sql : String
    "DOUBLE PRECISION"
  end

  def is_null_expression(expression : String) : String
    "#{expression} IS NULL"
  end

  def is_not_null_expression(expression : String) : String
    "#{expression} IS NOT NULL"
  end

  def identifier_quote_character : Char
    '"'
  end

  def string_literal_quote_character : Char
    '\''
  end

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
end
