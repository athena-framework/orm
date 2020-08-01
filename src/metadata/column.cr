module Athena::ORM::Metadata
  abstract struct ColumnBase
    def set_value(entity : AORM::Entity, value : _) : Nil
    end

    def get_value(entity : AORM::Entity)
      raise "BUG: Invoked default get_value"
    end
  end

  record Column(DefaultType, EntityType) < ColumnBase,
    name : String,
    type : AORM::Types::Type,
    nullable : Bool = false,
    is_primary_key : Bool = false,
    default : DefaultType? = nil,
    value_generator : ValueGeneratorMetadata? = nil,
    entity_class : EntityType.class = EntityType do
    def column_name : String
      # TODO: support reading column name off annotation
      @name
    end

    def table_name : String?
      # TODO: Set this when building the property
      "users"
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

    def set_value(entity : EntityType, value : _) : Nil
      {% begin %}
        case self.column_name
          {% for column in EntityType.instance_vars.select &.annotation AORM::Column %}
            when {{column.name.stringify}}
              if value.is_a? {{column.type}}
                pointerof(entity.@{{column.id}}).value = value
              end
          {% end %}
        end
      {% end %}
    end

    def get_value(entity : EntityType) : AORM::Metadata::Value
      {% begin %}
        {% for column in EntityType.instance_vars.select &.annotation AORM::Column %}
          case @name
            {% for column in EntityType.instance_vars.select &.annotation AORM::Column %}
              when {{column.name.stringify}} then AORM::Metadata::ColumnValue.new {{column.name.stringify}}, entity.@{{column.id}}
            {% end %}
          else
            raise "BUG: Unknown column"
          end
        {% end %}
      {% end %}
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
    include Enumerable(ColumnBase)
    include Iterable(ColumnBase)

    getter inheritence_type = InheritenceType::None
    @field_names = Hash(String, String).new
    @properties = Hash(String, ColumnBase).new

    getter entity_class : AORM::Entity.class
    getter table : Table
    getter identifier = Set(String).new
    getter value_generation_plan : AORM::ValueGenerationPlanInterface do
      executor_list = Hash(String, AORM::ValueGenerationExecutorInterface).new

      self.each do |property|
        executor = property.value_generation_executor

        if executor.is_a? ValueGenerationExecutorInterface
          executor_list[property.name] = executor
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

    def column(name : String) : ColumnBase?
      @properties.each_value do |property|
        return property if property.column_name == name
      end
    end

    def property(name : String) : ColumnBase?
      @properties[name]?
    end

    def is_identifier?(name : String)
      return false if @identifier.empty?

      unless self.is_identifier_composite?
        return name == self.single_identifier_field_name
      end

      @identifier.includes? name
    end

    def each(&)
      @properties.each_value do |property|
        yield property
      end
    end

    def each
      @properties.each
    end

    def root_class : AORM::Entity.class
      # This method allows adding parent types in the future
      @entity_class
    end

    def table_name : String
      @table.name
    end

    def single_identifier_field_name : String
      # TODO: Use proper exception types
      raise "PK is composite" if self.is_identifier_composite?
      raise "No PK is defined" if @identifier.empty?

      @identifier.first
    end

    def is_identifier_composite? : Bool
      @identifier.size > 1
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
