module Athena::ORM::Metadata
  abstract struct ColumnBase; end

  record Column(T) < ColumnBase,
    name : String,
    type : AORM::Types::Type,
    nullable : Bool = false,
    is_primary_key : Bool = false,
    default : T? = nil
end
