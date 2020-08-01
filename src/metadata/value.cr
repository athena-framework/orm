module Athena::ORM::Metadata
  abstract struct Value; end

  record ColumnValue(T) < Value, name : String, value : T do
    # forward_missing_to @value
  end
end
