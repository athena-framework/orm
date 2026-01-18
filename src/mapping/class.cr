require "./generated_value_strategy"

module Athena::ORM::Mapping::ClassInterface
  abstract def entity_class : AORM::Entity.class
  abstract def field_names : Hash(String, String)
  abstract def field_mappings : Hash(String, Field)
  abstract def identifier : Set(String)
  abstract def new_instance(data : Hash(String, DB::Any?)) : AORM::Entity
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

  def validate_and_complete(mapping : Driver::ColumnMapping, info : Class::FieldInfo(_, T, _)) : Driver::ColumnMapping forall T
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
  abstract struct FieldInfoBase; end

  # :nodoc:
  record FieldInfo(OwningEntity, IVarType, Idx) < FieldInfoBase, name : String, has_default : Bool, default : IVarType? do
    def apply_type_mapping(mapper : TypedFieldMapper, mapping : Driver::ColumnMapping) : Driver::ColumnMapping
      mapper.validate_and_complete(mapping, self) # self has concrete type here
    end

    def create_column_value(value : Mapping::Value) : Mapping::Value
      value
    end

    def create_column_value(value : IVarType) : Mapping::Value
      Mapping::ColumnValue(IVarType).new @name, value
    end

    def create_column_value(value : _) : NoReturn
      raise "BUG: Invoked wrong overload"
    end

    def create_column_value(entity : AORM::Entity) : Mapping::ColumnValue(IVarType)
      Mapping::ColumnValue(IVarType).new @name, self.get_value(entity)
    end

    def apply_type_association_mapping(mapper : TypedFieldMapper, mapping : Driver::ColumnMapping) : Driver::ColumnMapping
      {% begin %}
        {% ivar_type = IVarType.nilable? ? IVarType.union_types.reject(&.nilable?).first : IVarType %}

        {% if ivar_type <= AORM::Entity? %}
          mapping = mapping.copy_with target_entity: {{ivar_type}}
        {% end %}
      {% end %}

      mapping
    end

    def create_change(old_value : IVarType?, new_value : IVarType) : Athena::ORM::UnitOfWork::Change
      Athena::ORM::UnitOfWork::Change.new(
        old_value ? self.create_column_value(old_value) : nil,
        self.create_column_value(new_value),
      )
    end

    def create_change(old_value : _, new_value : _) : Athena::ORM::UnitOfWork::Change
      raise "BUG: Invoked wrong overload"
    end

    def get_value(entity : OwningEntity) : IVarType
      {% begin %}
        entity.@{{OwningEntity.instance_vars[Idx].name.id}}
      {% end %}
    end

    def get_value(entity : _) : NoReturn
      raise "BUG: Invoked wrong overload"
    end

    def set_value(entity : OwningEntity, value : IVarType) : Nil
      {% begin %}
        pointerof(entity.@{{OwningEntity.instance_vars[Idx].name.id}}).value = value
      {% end %}
    end

    def set_value(entity : _, value : _) : Nil
      raise "BUG: Invoked wrong overload"
    end
  end

  getter entity_class : AORM::Entity.class

  property custom_repository_class : AORM::RepositoryInterface.class | Nil
  property? read_only : Bool = false
  property id_generator_type : AORM::Mapping::GeneratedValueStrategy = :none
  property! id_generator : AORM::ID::AbstractGenerator

  property? embedded_class : Bool = false

  getter table : TableInfo

  getter field_mappings : Hash(String, Field) = Hash(String, Field).new
  getter association_mappings : Hash(String, OneToOneInverseSide | OneToOneOwningSide) = Hash(String, OneToOneInverseSide | OneToOneOwningSide).new

  # Maps column name => field name
  getter field_names : Hash(String, String) = Hash(String, String).new

  # This is internal references to each ivar
  protected getter field_info = Hash(String, FieldInfoBase).new

  # Fields that make up the primary key
  getter identifier : Set(String) = Set(String).new

  getter inheritance_type : InheritanceType = :none
  getter contains_foreign_identifier : Bool = false
  getter contains_enum_identifier : Bool = false
  getter is_identifier_composite : Bool = false
  getter? requires_fetch_after_change : Bool = false

  def initialize(
    @entity_class : AORM::Entity.class = T,
    naming_strategy : AORM::Mapping::NamingStrategyInterface? = nil,
  )
    # TODO: Handle naming strategy
    @table = TableInfo.new @entity_class.to_s.split("::").last.underscore
    @naming_strategy = naming_strategy || DefaultNamingStrategy.new

    {% for ivar, idx in T.instance_vars %}
      @field_info[{{ivar.name.id.stringify}}] = FieldInfo({{T}}, {{ivar.type}}, {{idx}}).new({{ivar.name.id.stringify}}, {{ivar.has_default_value?}}, {{ivar.default_value}})
    {% end %}
  end

  def new_instance(data : Hash(String, DB::Any?)) : AORM::Entity
    {% begin %}
      {% if T.abstract? %}
        raise "Cannot instantiate abstract entity {{T}}"
      {% else %}
        instance = T.allocate
        {% for ivar in T.instance_vars %}
          if data.has_key?({{ ivar.name.stringify }})
            raw = data[{{ ivar.name.stringify }}]
            {% if ivar.type.nilable? %}
              pointerof(instance.@{{ ivar.id }}).value = raw.as({{ ivar.type }})
            {% else %}
              pointerof(instance.@{{ ivar.id }}).value = raw.not_nil!.as({{ ivar.type }})
            {% end %}
          end
        {% end %}
        instance
      {% end %}
    {% end %}
  end

  def type_of_field(field_name : String) : String?
    (fm = @field_mappings[field_name]?) ? fm.type : nil
  end

  def single_identifier_field_name : String
    raise "single id not allowed on composite primary key" if @is_identifier_composite

    raise "no ID defined" unless id = @identifier.first?

    id
  end

  def single_identifier_column_name : String
    self.column_name(self.single_identifier_field_name)
  end

  def field_value(entity : T, field_name : String)
    @field_info[field_name].get_value entity
  end

  def field_value(entity : _, field_name : String) : NoReturn
    raise "BUG: Invoked wrong overload"
  end

  def is_identifier(field_name : String) : Bool
    return false if @identifier.empty?

    return field_name == @identifier.first if !@is_identifier_composite

    @identifier.includes? field_name
  end

  def identifier_values(entity : T) : Hash
    if @is_identifier_composite
      return @identifier.to_h do |k|
        {k, nil}
      end
    end

    id = @identifier.first
    value = @field_info[id].get_value entity

    if value.nil?
      return {} of String => NoReturn
    end

    {id => value}
  end

  # :nodoc:
  #
  # TODO: Is there a better way to handle this?
  def identifier_values(entity : _) : NoReturn
    raise "BUG: Invoked wrong overload"
  end

  def set_identifier_values(entity : T, id : Hash(String, _)) : Nil
    id.each do |id_field, id_value|
      @field_info[id_field].set_value entity, id_value
    end
  end

  # :nodoc:
  #
  # TODO: Is there a better way to handle this?
  def set_identifier_values(entity : _, id : Hash(String, _)) : NoReturn
    raise "BUG: Invoked wrong overload"
  end

  def identifier_natural? : Bool
    @id_generator_type.none?
  end

  def identifier_identity? : Bool
    @id_generator_type.identity?
  end

  def column_name(field_name : String) : String
    @field_mappings[field_name]?.try(&.column_name) || field_name
  end

  def table_name : String
    @table.name.not_nil!
  end

  def map_field(mapping : Driver::ColumnMapping) : Nil
    mapping = self.validate_and_complete_field_mapping mapping
    self.assert_field_not_mapped mapping.field_name

    if mapping.generated == true
      @requires_fetch_after_change = true
    end

    @field_mappings[mapping.field_name] = mapping
  end

  private def validate_and_complete_field_mapping(mapping : Driver::ColumnMapping) : Field
    raise "Missing field name" if mapping.field_name.nil?

    # mapping = TypedFieldMapper.new.validate_and_complete(mapping, @field_info[mapping.field_name])
    mapping = @field_info[mapping.field_name].apply_type_mapping TypedFieldMapper.new, mapping

    if mapping.type.nil?
      mapping = mapping.copy_with type: "string"
    end

    if mapping.column_name.nil?
      mapping = mapping.copy_with column_name: @naming_strategy.property_to_column_name(mapping.field_name, @entity_class)
    end

    mapping = Field.from_column_mapping mapping

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

  def map_one_to_one(mapping : Driver::ColumnMapping) : Nil
    mapping = mapping.copy_with type: "one_to_one"

    mapping = self.validate_and_complete_association_mapping mapping

    self.store_association_mapping mapping
  end

  def validate_and_complete_association_mapping(mapping : Driver::ColumnMapping) : Association
    # TODO: Handle unsetting things?

    mapping = mapping.copy_with is_owning_side: true, source_entity: @entity_class
    mapping = @field_info[mapping.field_name].apply_type_association_mapping TypedFieldMapper.new, mapping

    if "many_to_one" == mapping.type && mapping.orphan_removal
      raise "illegal orphan removal"
    end

    # TODO: Handle PK FKs

    raise "Missing field name" if mapping.field_name.nil?
    raise "Missing target entity" if mapping.target_entity.nil?

    if !(mapped_by = mapping.mapped_by) # && !(join_table = mapping.join_table)
      # TODO: Handle join table info
    else
      mapping = mapping.copy_with is_owning_side: false
    end

    if mapping.id && mapping.type.try &.ends_with? "to_many"
      raise "illegal to many identifier association"
    end

    unless mapping.fetch_mode
      mapping = mapping.copy_with fetch_mode: FetchMode::LAZY
    end

    # TODO: Handle cascades

    case mapping.type
    when "one_to_one"
      mapping.is_owning_side ? OneToOneOwningSide.new(
        mapping,
        @naming_strategy,
        @entity_class,
        @table,
        self.inheritance_type.single_table?
      ) : OneToOneInverseSide.new mapping
    else
      raise "Invalid association type"
    end
  end

  def store_association_mapping(mapping : Association) : Nil
    self.assert_field_not_mapped source_field_name = mapping.field_name

    @association_mappings[source_field_name] = mapping
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
      else
        @table = @table.copy_with name: name
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
