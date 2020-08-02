module Athena::ORM::Mapping::Annotations
  protected record Column,
    name : String? = nil,
    type : AORM::Types::Type? = nil,
    length : Int32 = 255,
    precision : Int32 = 0,
    scale : Int32 = 0,
    unique : Bool = false,
    nilable : Bool = false,
    column_definition : String? = nil

  protected record ID
  protected record GeneratedValue, strategy : AORM::Mapping::GeneratorType = :auto
  protected record SequenceGenerator, name : String, allocation_size : Int64 = 1
end
