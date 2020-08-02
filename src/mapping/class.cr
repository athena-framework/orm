require "./column"

module Athena::ORM::Mapping
  enum InheritenceType
    None
  end

  enum ChangeTrackingPolicy
    DeferredImplicit
  end

  abstract class ClassBase; end

  class Class(EntityType) < ClassBase
    include Enumerable(Athena::ORM::Mapping::ColumnBase)
    include Iterable(Athena::ORM::Mapping::ColumnBase)

    protected def self.build_metadata(context : ClassFactory::Context) : self
      table_annotation = {% if ann = EntityType.annotation(AORMA::Table) %}AORM::Mapping::Annotations::Table.new({{ann.named_args.double_splat}}){% else %}nil{% end %}

      metadata = new(
        Table.build_metadata context, EntityType, table_annotation
      )

      {% for column, idx in EntityType.instance_vars.select &.annotation AORMA::Column %}
        {% ann = column.annotation AORMA::Column %}
        {% type = ann[:type] == nil ? (column.type.union? ? column.type.union_types.first : column.type) : ann[:type] %}

        %property{idx} = AORM::Mapping::Column({{type}}, {{EntityType}}).build_metadata(
          context,
          {{column.name.stringify}},
          metadata,
          {% if ann = column.annotation(AORMA::Column) %}column: AORM::Mapping::Annotations::Column.new({{ann.named_args.double_splat}}),{% end %}
          {% if column.annotation(AORMA::ID) %}id: AORM::Mapping::Annotations::ID.new,{% end %}
          {% if ann = column.annotation(AORMA::GeneratedValue) %}generated_value: AORM::Mapping::Annotations::GeneratedValue.new({{ann.named_args.double_splat}}){% end %}
          {% if ann = column.annotation(AORMA::SequenceGenerator) %}sequence_generator: AORM::Mapping::Annotations::SequenceGenerator.new({{ann.named_args.double_splat}}){% end %}
        )

        metadata.add_property %property{idx}
      {% end %}

      metadata.determine_value_generation_plan context.target_platform

      metadata
    end

    getter inheritence_type = AORM::Mapping::InheritenceType::None
    @field_names = Hash(String, String).new
    @properties = Hash(String, AORM::Mapping::ColumnBase).new

    getter entity_class : AORM::Entity.class
    getter table : AORM::Mapping::Table
    getter identifier = Set(String).new
    getter value_generation_plan : AORM::Sequencing::Planning::Interface = AORM::Sequencing::Planning::Noop.new

    def initialize(
      @table : AORM::Mapping::Table,
      @entity_class : AORM::Entity.class = EntityType
    ); end

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

    def schema_name : String?
      @table.schema
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

    protected def determine_value_generation_plan(target_platform : AORM::Platforms::Platform) : Nil
      executor_list = Hash(String, AORM::Sequencing::Executors::Interface).new

      generated_value_count = self.each.count do |name, property|
        executor = property.value_generation_executor(target_platform)

        if executor.is_a? AORM::Sequencing::Executors::Interface
          executor_list[name] = executor
        end
      end

      return if executor_list.empty?

      @value_generation_plan = case executor_list.size
                               when 1 then AORM::Sequencing::Planning::SingleValue.new self, executor_list.values.first
                               else        raise "TODO: Support generating composite values"
                               end
    end
  end
end
