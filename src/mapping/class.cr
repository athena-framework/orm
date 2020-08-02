require "./column"
require "./table"

module Athena::ORM::Mapping
  enum InheritenceType
    None
  end

  enum ChangeTrackingPolicy
    DeferredImplicit
  end

  struct Class
    include Enumerable(Athena::ORM::Mapping::ColumnBase)
    include Iterable(Athena::ORM::Mapping::ColumnBase)

    getter inheritence_type = AORM::Mapping::InheritenceType::None
    @field_names = Hash(String, String).new
    @properties = Hash(String, AORM::Mapping::ColumnBase).new

    getter entity_class : AORM::Entity.class
    getter table : AORM::Mapping::Table
    getter identifier = Set(String).new
    getter value_generation_plan : AORM::Sequencing::Planning::Interface do
      executor_list = Hash(String, AORM::ValueGenerationExecutorInterface).new

      self.each do |property|
        executor = property.value_generation_executor

        if executor.is_a? AORM::ValueGenerationExecutorInterface
          executor_list[property.name] = executor
        end
      end

      case executor_list.size
      when 1 then AORM::SingleValueGenerationPlan.new self, executor_list.values.first
      else
        raise "ERR"
      end
    end

    def initialize(@entity_class : AORM::Entity.class, @table : AORM::Mapping::Table)
    end

    def add_property(property : AORM::Mapping::ColumnBase) : Nil
      @identifier << property.name if property.is_primary_key

      # TODO: Handle duplicate property
      # property.declaring_class = self

      @properties[property.name] = property
    end

    def column(name : String) : AORM::Mapping::ColumnBase?
      @properties.each_value do |property|
        return property if property.column_name == name
      end
    end

    def property(name : String) : AORM::Mapping::ColumnBase?
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

    def custom_repository_class : AORM::EntityRepository.class | Nil
      nil
    end

    def default_repository_class : AORM::EntityRepository.class
      AORM::EntityRepository
    end
  end
end
