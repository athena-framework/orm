module Athena::ORM::Metadata
  abstract struct ColumnBase; end

  record Column(T) < ColumnBase,
    name : String,
    type : AORM::Types::Type,
    nullable : Bool = false,
    is_primary_key : Bool = false,
    default : T? = nil do
    # property! declaring_class : Class

    def column_name : String
      # TODO: support reading column name off annotation
      @name
    end
  end

  record Table, name : String, schema : String? = nil do
    def quoted_qualified_name(platform : AORM::Platforms::Platform) : String
      unless @schema
        return platform.quote_identifier @name
      end

      seperator = !platform.supports_schemas? && platform.can_emulate_schemas? ? "__" : "."

      platform.quote_identifier "#{@schema}#{seperator}#{@name}"
    end
  end

  enum InheritenceType
    None
  end

  enum ChangeTrackingPolicy
    DeferredImplicit
  end

  struct Class
    getter inheritence_type = InheritenceType::None
    @field_names = Hash(String, String).new
    @identifier = Set(String).new
    @properties = Hash(String, ColumnBase).new

    getter entity_class : AORM::Entity.class
    getter table : Table

    def initialize(@entity_class : AORM::Entity.class, @table : Table); end

    def add_property(property : ColumnBase) : Nil
      @identifier << property.name if property.is_primary_key

      # TODO: Handle duplicate property
      # property.declaring_class = self

      @properties[property.name] = property
    end

    def each_property(&) : Nil
      @properties.each do |name, property|
        yield name, property
      end
    end

    def root_class : AORM::Entity.class
      # This method allows adding parent types in the future
      @entity_class
    end
  end
end
