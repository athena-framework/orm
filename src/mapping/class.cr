# require "./column"

module Athena::ORM::Mapping::ClassInterface
  abstract def entity_class : AORM::Entity.class
end

private struct Athena::ORM::Mapping::TypedFieldMapper
  DEFAULT_TYPE_FIELD_MAPPINGS = {
    ::String => "string",
    ::Bool   => "boolean",
    ::Int64  => "integer",
  }

  @typed_field_mappings : Hash(String, String)

  def initialize(typed_field_mappings : Hash(String, String) = {} of String => String)
    typed_field_mappings = Hash(String, String).new

    DEFAULT_TYPE_FIELD_MAPPINGS.each do |name, type|
      typed_field_mappings[name.to_s] = type
    end

    typed_field_mappings.each do |name, type|
      typed_field_mappings[name.to_s] = type
    end

    @typed_field_mappings = typed_field_mappings
  end

  def validate_and_complete(mapping : Driver::ColumnMapping, info : Class::FieldInfo(T, I)) : Driver::ColumnMapping forall T, I
    return mapping unless mapping.type.nil?

    if type = @typed_field_mappings[{{ T.nilable? ? T.union_types.reject(&.nilable?).first.stringify : T.stringify }}]?
      mapping = mapping.copy_with type: type
    end

    mapping
  end

  def validate_and_complete(mapping : Driver::ColumnMapping, info : Class::FieldInfoBase) : NoReturn
    raise "BUG: Invoked wrong overload"
  end
end

class Athena::ORM::Mapping::Class(T)
  include Athena::ORM::Mapping::ClassInterface

  # :nodoc:
  record TableInfo, name : String? = nil, schema : String? = nil, indexes : Array(String)? = nil, unique_constraints : Array(String)? = nil, quoted : Bool = false

  # :nodoc:
  abstract struct FieldInfoBase
    abstract def apply_type_mapping(mapper : TypedFieldMapper, mapping : Driver::ColumnMapping) : Driver::ColumnMapping
  end

  # :nodoc:
  record FieldInfo(IVarType, Idx) < FieldInfoBase, has_default : Bool, default : IVarType? do
    def apply_type_mapping(mapper : TypedFieldMapper, mapping : Driver::ColumnMapping) : Driver::ColumnMapping
      mapper.validate_and_complete(mapping, self) # self has concrete type here
    end
  end

  getter entity_class : AORM::Entity.class

  property custom_repository_class : AORM::RepositoryInterface.class | Nil
  property? read_only : Bool = false
  property id_generator_type : AORM::Mapping::Annotations::GeneratedValue::Strategy = :none
  property! id_generator : AORM::ID::AbstractGenerator

  @table : TableInfo

  getter field_mappings = Hash(String, FieldMapping).new

  # Maps column name to field name
  @field_names = Hash(String, String).new

  # This is internal references to each ivar
  @field_info = Hash(String, FieldInfoBase).new

  # Fields that make up the primary key
  getter identifier = Set(String).new

  @is_identifier_composite : Bool = false

  def initialize(
    @entity_class : AORM::Entity.class = T,
  )
    # TODO: Handle naming strategy
    @table = TableInfo.new @entity_class.to_s.split("::").last.underscore

    {% for ivar, idx in T.instance_vars %}
      @field_info[{{ivar.name.id.stringify}}] = FieldInfo({{ivar.type}}, {{idx}}).new({{ivar.has_default_value?}}, {{ivar.default_value}})
    {% end %}
  end

  def single_identifier_field_name : String
    raise "single id not allowed on composite primary key" if @is_identifier_composite

    raise "no ID defined" unless id = @identifier.first?

    id
  end

  def single_identifier_column_name : String
    self.column_name(self.single_identifier_field_name)
  end

  def column_name(field_name : String) : String
    @field_mappings[field_name]?.try(&.column_name) || field_name
  end

  def map_field(mapping : Driver::ColumnMapping) : Nil
    mapping = self.validate_and_complete_field_mapping mapping
    self.assert_field_not_mapped mapping.field_name

    if mapping.generated == true
      @requires_fetch_after_change = true
    end

    @field_mappings[mapping.field_name] = mapping
  end

  private def validate_and_complete_field_mapping(mapping : Driver::ColumnMapping) : FieldMapping
    raise "Missing field name" if mapping.field_name.nil?

    # mapping = TypedFieldMapper.new.validate_and_complete(mapping, @field_info[mapping.field_name])
    mapping = @field_info[mapping.field_name].apply_type_mapping TypedFieldMapper.new, mapping

    if mapping.type.nil?
      mapping = mapping.copy_with type: "string"
    end

    if mapping.column_name.nil?
      # TODO: Handle naming strategy
      mapping = mapping.copy_with column_name: mapping.field_name
    end

    mapping = FieldMapping.from_column_mapping mapping

    if mapping.column_name.starts_with?('`')
      mapping = mapping.copy_with column_name: mapping.column_name.strip('`'), quoted: true
    end

    # TODO: Handle discriminator maps
    if @field_names.has_key? mapping.column_name
      raise "Duplicate column name '#{mapping.column_name}'."
    end

    @field_names[mapping.column_name] = mapping.field_name

    if mapping.id == true
      # TODO: Handle version field
      @identifier << mapping.field_name

      if !@is_identifier_composite && @identifier.size > 1
        @is_identifier_composite = true
      end
    end

    # TODO: Handle `generated` property

    # TODO: Handle `enum_type` property

    mapping
  end

  private def assert_field_not_mapped(field_name : String)
    if @field_mappings.has_key? field_name
      raise "Duplicate field mapping '#{field_name}'."
    end
  end

  def primary_table=(table : Driver::TableMapping) : Nil
    if name = table.name
      # TODO: Handle myschema.mytable

      if name.starts_with?('`')
        @table = @table.copy_with name: name.strip('`'), quoted: true
      end
    end

    if quoted = table.quoted
      @table = @table.copy_with quoted: quoted
    end

    if schema = table.schema
      @table = @table.copy_with schema: schema
    end

    # TODO: Handle indexes, unique_constraints, and options
  end
end

# module Athena::ORM::Mapping
#   abstract class ClassBase; end

#   class Class(EntityType) < ClassBase
#     include Enumerable(Athena::ORM::Mapping::ColumnMetadata)

#     protected def self.build_metadata(context : ClassFactory::Context) : self
#       table_annotation = {% if ann = EntityType.annotation(AORMA::Table) %}AORM::Mapping::Annotations::Table.new({{ann.named_args.double_splat}}){% else %}nil{% end %}
#       entity_annotation = {% if ann = EntityType.annotation(AORMA::Entity) %}AORM::Mapping::Annotations::Entity.new({{ann.named_args.double_splat}}){% else %}nil{% end %}

#       metadata = new(
#         Table.build_metadata(context, EntityType, table_annotation),
#         entity_annotation.try &.repository_class
#       )

#       {% for column, idx in EntityType.instance_vars %}
#         {% type = column.type.union? ? column.type.union_types.reject(&.==(Nil)).first : column.type %}

#         %property{idx} = nil

#         {% if column_ann = column.annotation AORMA::Column %}
#           {% type = column_ann[:type] == nil ? type : column_ann[:type] %}

#           %property{idx} = AORM::Mapping::FieldMetadata({{type}}, {{EntityType}}).build_metadata(
#             context,
#             {{column.name.stringify}},
#             metadata,
#             {% if ann = column.annotation(AORMA::Column) %}column: AORM::Mapping::Annotations::Column.new({{ann.named_args.double_splat}}),{% end %}
#             {% if column.annotation(AORMA::ID) %}id: AORM::Mapping::Annotations::ID.new,{% end %}
#             {% if ann = column.annotation(AORMA::GeneratedValue) %}generated_value: AORM::Mapping::Annotations::GeneratedValue.new({{ann.named_args.double_splat}}){% end %}
#             {% if ann = column.annotation(AORMA::SequenceGenerator) %}sequence_generator: AORM::Mapping::Annotations::SequenceGenerator.new({{ann.named_args.double_splat}}){% end %}
#           )
#         {% elsif one_to_one_annotation = column.annotation AORMA::OneToOne %}
#           {% target_entity = one_to_one_annotation[:target_entity] != nil ? one_to_one_annotation[:target_entity] : type %}

#           %property{idx} = AORM::Mapping::OneToOneAssociationMetadata({{EntityType}}, {{target_entity}}).build_metadata(
#             context,
#             {{column.name.stringify}},
#             metadata,
#             {% if ann = column.annotation(AORMA::OneToOne) %}one_to_one: AORM::Mapping::Annotations::OneToOne.new({{ann.named_args.double_splat}}),{% end %}
#             {% if column.annotation(AORMA::ID) %}id: AORM::Mapping::Annotations::ID.new,{% end %}
#           )
#         {% end %}

#         if p = %property{idx}
#           metadata.add_property p
#         end
#       {% end %}

#       metadata.determine_id_generator context.target_platform

#       metadata
#     end

#     @properties = Hash(String, AORM::Mapping::Property).new
#     getter field_names = Hash(String, String).new

#     getter entity_class : AORM::Entity.class
#     getter custom_repository_class : AORM::RepositoryInterface.class | Nil
#     getter table : AORM::Mapping::Table
#     getter identifier = Set(String).new
#     getter id_generator : AORM::ID::AbstractGenerator? = nil

#     def initialize(
#       @table : AORM::Mapping::Table,
#       @custom_repository_class : AORM::RepositoryInterface.class | Nil = nil,
#       @entity_class : AORM::Entity.class = EntityType
#     ); end

#     def add_property(property : AORM::Mapping::Property) : Nil
#       case property
#       in FieldMetadata
#         @field_names[property.column_name] = property.name
#       in ToOneAssociationMetadata
#         property.join_columns.each do |join_column|
#           @field_names[join_column.column_name] = property.name
#         end
#       end

#       @identifier << property.name if property.is_primary_key?

#       # TODO: Handle duplicate property
#       # property.declaring_class = self

#       @properties[property.name] = property
#     end

#     def column(name : String) : AORM::Mapping::ColumnMetadata?
#       @properties.each_value do |property|
#         case property
#         when FieldMetadata then return property if property.column_name == name
#         when ToOneAssociationMetadata
#           property.join_columns.each do |join_column|
#             return join_column if join_column.column_name == name
#           end
#         end
#       end
#     end

#     def property(name : String) : AORM::Mapping::Property?
#       @properties[name]?
#     end

#     def is_identifier?(name : String)
#       return false if @identifier.empty?

#       unless self.is_identifier_composite?
#         return name == self.single_identifier_field_name
#       end

#       @identifier.includes? name
#     end

#     def map_each_property
#       @properties.compact_map do |_name, property|
#         yield property
#       end
#     end

#     def each(&)
#       @properties.each_value do |property|
#         yield property
#       end
#     end

#     def each
#       @properties.each
#     end

#     def root_class : AORM::Entity.class
#       # This method allows adding parent types in the future
#       @entity_class
#     end

#     def table_name : String
#       @table.name
#     end

#     def schema_name : String?
#       @table.schema
#     end

#     def single_identifier_field_name : String
#       # TODO: Use proper exception types
#       raise "PK is composite" if self.is_identifier_composite?
#       raise "No PK is defined" if @identifier.empty?

#       @identifier.first
#     end

#     def is_identifier_composite? : Bool
#       @identifier.size > 1
#     end

#     def default_repository_class : AORM::RepositoryInterface.class
#       AORM::EntityRepository(AORM::Entity)
#     end

#     protected def determine_id_generator(target_platform : AORM::Platforms::Platform) : Nil
#       self.each do |property|
#         if property.has_value_generator?
#           if vg = property.value_generator
#             @id_generator = vg.generator
#             return # Only support single ID column for now
#           end
#         end
#       end
#     end
#   end
# end
