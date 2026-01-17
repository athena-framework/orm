module Athena::ORM::Mapping
  abstract struct Value; end

  record ColumnValue(T) < Athena::ORM::Mapping::Value, name : String, value : T
end
