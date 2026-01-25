module Athena::ORM::Mapping
  # Container type for holding arbitrary values for a given column

  abstract struct Value
    abstract def value
  end

  record SingleValue(T) < Athena::ORM::Mapping::Value, value : T

  record ColumnValue(T) < Athena::ORM::Mapping::Value, name : String, value : T do
    forward_missing_to @value

    def to_s(io : IO) : Nil
      @value.to_s io
    end

    def inspect(io : IO) : Nil
      @value.inspect io
    end
  end
end
