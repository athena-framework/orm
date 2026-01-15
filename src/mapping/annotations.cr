module Athena::ORM::Mapping::Annotations
  protected record Column,
    name : String? = nil,
    type_class : AORM::Types::Type.class | Nil = nil,
    nilable : Bool = false

  protected record ID
  protected record MappedSuperclass, entity_class : AORM::Entity.class
  protected record Embeddable
  protected record GeneratedValue, strategy : Strategy = :auto do
    enum Strategy
      AUTO
      SEQUENCE
      IDENTITY
      NONE
      CUSTOM
    end
  end
  protected record SequenceGenerator, name : String, allocation_size : Int64 = 1
  protected record Table, name : String? = nil, schema : String? = nil
  protected record Entity, repository_class : AORM::RepositoryInterface.class | Nil = nil, read_only : Bool = false
  protected record OneToOne,
    target_entity : AORM::Entity.class | Nil = nil,
    fetch_mode : FetchMode = :lazy,
    mapped_by : String? = nil,
    inversed_by : String? = nil,
    orphan_removal : Bool = false do
    enum FetchMode
      LAZY
      EAGER
      EXTRA_LAZY
    end
  end
end
