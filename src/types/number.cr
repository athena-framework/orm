# `BigDecimal` requires linking libgmp, so this type only exists for programs that `require "big"` themselves.
macro finished
  {% if @top_level.has_constant?("BigDecimal") %}
    # Holds decimal values as `BigDecimal`s.
    struct Athena::ORM::Types::Number < Athena::ORM::Types::Type
      # :inherit:
      def sql_declaration(column : Schema::Column, platform : AORM::Platforms::Platform) : ::String
        platform.decimal_type_declaration_sql column
      end

      # Drivers can't bind `BigDecimal`, but accept its string form for decimal columns.
      def to_db(value : _, platform : AORM::Platforms::Platform)
        value.is_a?(::BigDecimal) ? value.to_s : value
      end

      # :inherit:
      def to_crystal_value(value : _, platform : Platforms::Platform) : ::BigDecimal?
        case value
        when Nil, ::BigDecimal       then value
        when ::String, ::Int         then ::BigDecimal.new value
        when ::Bool, ::Time, Bytes   then raise "Number cannot accept #{value.class}"
        else
          # SQLite can return a decimal column as a float, and Postgres as a `PG::Numeric`.
          # A float's shortest representation is the decimal it was read from.
          ::BigDecimal.new value.to_s
        end
      end

      # :inherit:
      def to_crystal_value(value : DB::ResultSet, platform : Platforms::Platform) : ::BigDecimal?
        self.to_crystal_value value.read, platform
      end
    end
  {% end %}
end
