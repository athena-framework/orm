module Athena::ORM::Mapping::Annotations
  protected record Column,
    name : String? = nil,
    type_class : AORM::Types::Type.class | Nil = nil,
    nilable : Bool = false

  protected record ID
  protected record GeneratedValue, strategy : AORM::Mapping::GeneratorType = :auto
  protected record SequenceGenerator, name : String, allocation_size : Int64 = 1
  protected record Table, name : String
  protected record Entity, repository_class : AORM::RepositoryInterface.class | Nil = nil
  protected record OneToOne,
    target_entity : AORM::Entity.class | Nil = nil,
    fetch_mode : FetchMode = :lazy,
    mapped_by : String? = nil,
    inversed_by : String? = nil,
    orphan_removal : Bool = false
end
