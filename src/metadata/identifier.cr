module Athena::ORM::Metadata
  abstract struct Identifier; end

  record ColumnIdentifier(T) < Identifier, name : String, value : T
end
