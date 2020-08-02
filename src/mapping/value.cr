module Athena::ORM::Mapping
  abstract struct Value; end

  record ColumnValue(T) < Athena::ORM::Mapping::Value, name : String, value : T do
    # forward_missing_to @value
  end
end
