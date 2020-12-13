struct Athena::ORM::Types::TypeRegistry
  @types = Hash(AORM::Types::Type.class, AORM::Types::Type).new

  def get(type_class : AORM::Types::Type.class) : AORM::Types::Type
    @types[type_class]
  end

  def get(type_class) : AORM::Types::Type
    @types[crystal_to_orm_type type_class]
  end

  def add(type_class : AORM::Types::Type.class, type : AORM::Types::Type) : Nil
    @types[type_class] = type
  end

  def add(type_class, type : AORM::Types::Type) : Nil
    @types[crystal_to_orm_type type_class] = type
  end

  private def crystal_to_orm_type(crystal_type) : AORM::Types::Type.class
    case crystal_type
    in ::Bool.class              then AORM::Types::Boolean
    in ::Int64.class             then AORM::Types::BigInt
    in ::String.class            then AORM::Types::String
    in ::AORM::Types::Type.class then AORM::Types::String
    end
  end
end
