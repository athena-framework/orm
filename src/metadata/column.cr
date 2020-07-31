module Athena::ORM::Metadata
  abstract struct ColumnBase; end

  record Column(T) < ColumnBase,
    name : String,
    type : AORM::Types::Type,
    nullable : Bool = false,
    is_primary_key : Bool = false,
    default : T? = nil,
    value_generator : ValueGeneratorMetadata? = nil do
    # property! declaring_class : Class

    def column_name : String
      # TODO: support reading column name off annotation
      @name
    end

    def has_value_generator? : Bool
      !@value_generator.nil?
    end

    def value_generation_executor : AORM::ValueGenerationExecutorInterface?
      # TODO: Pass in the platform to this method

      if generator = @value_generator
        AORM::ColumnValueGeneratorExecutor.new self, generator.generator
      end
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
    @properties = Hash(String, ColumnBase).new

    getter entity_class : AORM::Entity.class
    getter table : Table
    getter identifier = Set(String).new
    getter value_generation_plan : AORM::ValueGenerationPlanInterface do
      executor_list = Hash(String, AORM::ValueGenerationExecutorInterface).new

      self.each_property do |name, property|
        executor = property.value_generation_executor

        if executor.is_a? ValueGenerationExecutorInterface
          executor_list[name] = executor
        end
      end

      case executor_list.size
      when 1 then AORM::SingleValueGenerationPlan.new self, executor_list.values.first
      else
        raise "ERR"
      end
    end

    def initialize(@entity_class : AORM::Entity.class, @table : Table)
    end

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

    def table_name : String
      @table.name
    end
  end

  enum GeneratorType
    None
    Auto
    Sequence
    Table
    Identity
    Custom
  end

  record ValueGeneratorMetadata,
    type : GeneratorType,
    generator : AORM::GeneratorInterface
end
