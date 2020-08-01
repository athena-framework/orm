module Athena::ORM::Metadata
  abstract struct Value; end

  record ColumnValue(T) < Value, name : String, value : T
end
