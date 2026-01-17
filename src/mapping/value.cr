module Athena::ORM::Mapping
  # Container type for holding arbitrary values for a given column

  abstract struct Value; end

  record ColumnValue(T) < Athena::ORM::Mapping::Value, name : String, value : T
end
