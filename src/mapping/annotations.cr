module Athena::ORM::Mapping::Annotations
  protected record Column,
    name : String? = nil,
    type : String? = nil,
    length : Int32? = nil,
    precision : Int32? = nil,
    scale : Int32? = nil,
    unique : Bool = false,
    nullable : Bool = false,
    insertable : Bool = true,
    updatable : Bool = true,
    enum_type : String? = nil,
    column_definition : String? = nil,
    generated : String? = nil,
    index : Bool = false
  # options : Hash(String, String)

  protected record JoinColumn,
    name : String? = nil,
    referenced_column_name : String? = nil,
    deferable : Bool = false,
    unique : Bool = false,
    nullable : Bool = false,
    column_definition : String? = nil,
    field_name : String? = nil
  # on_delete : Any
  # options : Hash(String, String)

  protected record ID
  protected record MappedSuperclass, entity_class : AORM::Entity.class
  protected record Embeddable
  protected record GeneratedValue, strategy : GeneratedValueStrategy = :auto
  protected record SequenceGenerator, name : String, allocation_size : Int64 = 1
  protected record Table, name : String? = nil, schema : String? = nil
  protected record Entity, repository_class : AORM::RepositoryInterface.class | Nil = nil, read_only : Bool = false
  protected record OneToOne,
    target_entity : AORM::Entity.class | Nil = nil,
    fetch_mode : FetchMode = :lazy,
    mapped_by : String? = nil,
    inversed_by : String? = nil,
    orphan_removal : Bool = false,
    cascade : Array(String)? = nil
end
