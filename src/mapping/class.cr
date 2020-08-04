require "./column"

module Athena::ORM::Mapping
  abstract class ClassBase; end

  class Class(EntityType) < ClassBase
    include Enumerable(Athena::ORM::Mapping::ColumnBase)

    protected def self.build_metadata(context : ClassFactory::Context) : self
      table_annotation = {% if ann = EntityType.annotation(AORMA::Table) %}AORM::Mapping::Annotations::Table.new({{ann.named_args.double_splat}}){% else %}nil{% end %}
      entity_annotation = {% if ann = EntityType.annotation(AORMA::Entity) %}AORM::Mapping::Annotations::Entity.new({{ann.named_args.double_splat}}){% else %}nil{% end %}

      metadata = new(
        Table.build_metadata(context, EntityType, table_annotation),
        entity_annotation.try &.repository_class
      )

      {% for column, idx in EntityType.instance_vars %}
        {% type = column.type.union? ? column.type.union_types.reject(&.==(Nil)).first : column.type %}

        %property{idx} = nil

        {% if column_ann = column.annotation AORMA::Column %}
          {% type = column_ann[:type] == nil ? type : column_ann[:type] %}

          %property{idx} = AORM::Mapping::Column({{type}}, {{EntityType}}).build_metadata(
            context,
            {{column.name.stringify}},
            metadata,
            {% if ann = column.annotation(AORMA::Column) %}column: AORM::Mapping::Annotations::Column.new({{ann.named_args.double_splat}}),{% end %}
            {% if column.annotation(AORMA::ID) %}id: AORM::Mapping::Annotations::ID.new,{% end %}
            {% if ann = column.annotation(AORMA::GeneratedValue) %}generated_value: AORM::Mapping::Annotations::GeneratedValue.new({{ann.named_args.double_splat}}){% end %}
            {% if ann = column.annotation(AORMA::SequenceGenerator) %}sequence_generator: AORM::Mapping::Annotations::SequenceGenerator.new({{ann.named_args.double_splat}}){% end %}
          )
        {% elsif one_to_one_annotation = column.annotation AORMA::OneToOne %}
          {% target_entity = one_to_one_annotation[:target_entity] != nil ? one_to_one_annotation[:target_entity] : type %}

          %property{idx} = AORM::Mapping::Association({{EntityType}}, {{target_entity}}).build_metadata(
            context,
            {{column.name.stringify}},
            metadata,
            {% if ann = column.annotation(AORMA::OneToOne) %}one_to_one: AORM::Mapping::Annotations::OneToOne.new({{ann.named_args.double_splat}}),{% end %}
            {% if column.annotation(AORMA::ID) %}id: AORM::Mapping::Annotations::ID.new,{% end %}
          )
        {% end %}

        if p = %property{idx}
          metadata.add_property p
        end
      {% end %}

      metadata.determine_value_generation_plan context.target_platform

      metadata
    end

    @properties = Hash(String, AORM::Mapping::Property).new
    @field_names = Hash(String, String).new

    getter entity_class : AORM::Entity.class
    getter custom_repository_class : AORM::RepositoryInterface.class | Nil
    getter table : AORM::Mapping::Table
    getter identifier = Set(String).new
    getter value_generation_plan : AORM::Sequencing::Planning::Interface = AORM::Sequencing::Planning::Noop.new

    def initialize(
      @table : AORM::Mapping::Table,
      @custom_repository_class : AORM::RepositoryInterface.class | Nil = nil,
      @entity_class : AORM::Entity.class = EntityType
    ); end

    def add_property(property : AORM::Mapping::Property) : Nil
      case property
      in Column
        @field_names[property.column_name] = property.name
      in Association
        property.join_columns.each do |join_column|
          @field_names[join_column.column_name] = property.name
        end
      end

      @identifier << property.name if property.is_primary_key

      # TODO: Handle duplicate property
      # property.declaring_class = self

      @properties[property.name] = property
    end

    def column(name : String) : AORM::Mapping::Property?
      @properties.each_value do |property|
        return property if property.column_name == name
      end
    end

    def property(name : String) : AORM::Mapping::Property?
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

    def default_repository_class : AORM::RepositoryInterface.class
      AORM::EntityRepository(AORM::Entity)
    end

    protected def determine_value_generation_plan(target_platform : AORM::Platforms::Platform) : Nil
      executor_list = Hash(String, AORM::Sequencing::Executors::Interface).new

      self.each do |property|
        executor = property.value_generation_executor(target_platform)

        if executor.is_a? AORM::Sequencing::Executors::Interface
          executor_list[property.name] = executor
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
