class Athena::ORM::Query::Hints
  # Hint used to collect all primary keys of associated entities during hydration and execute it in a dedicated query afterwards
  property? defer_eager_load : Bool? = nil
  getter! collection : AORM::PersistentCollectionInterface
  property! fetch_alias : String

  def initialize(
    @defer_eager_load : Bool? = nil,
    @collection : AORM::PersistentCollectionInterface? = nil,
  ); end
end

# TODO: Maybe see about making this generic to more accurately type what `hydrate_all` returns?
abstract class Athena::ORM::Internal::Hydrators::Abstract
  # :nodoc:
  record ColumnInfo, field_name : String, type : Types::Type?, alias_name : String, is_identifier : Bool # enum_type

  private getter! rsm : AORM::Query::ResultSetMapping
  @platform : AORM::Platforms::Platform
  @uow : AORM::UnitOfWork
  @metadata_cache = Hash(AORM::Entity.class, Mapping::ClassInterface).new.compare_by_identity

  @cache : Hash(String, ColumnInfo) = Hash(String, ColumnInfo).new

  private getter! rs : DB::ResultSet
  @hints : Query::Hints = Query::Hints.new

  def initialize(@em : AORM::EntityManagerInterface)
    @platform = @em.connection.database_platform
    @uow = @em.unit_of_work
  end

  # Hydrates all rows using ResultSetMapping.
  def hydrate_all(
    @rs : DB::ResultSet,
    @rsm : AORM::Query::ResultSetMapping,
    hints : Query::Hints = Query::Hints.new,
  ) : Array
    @rs = rs
    @rsm = rsm
    @hints = hints

    self.prepare

    begin
      self.hydrate_all_data
    ensure
      self.cleanup
    end
  end

  # Hydrates all rows from the current result set.
  # Children implement this with their specific hydration logic.
  protected abstract def hydrate_all_data : Array

  protected def hydrate_column_info(key : String) : ColumnInfo?
    if ci = @cache[key]?
      return ci
    end

    if field_name = self.rsm.field_mappings[key]?
      class_metadata = self.class_metadata self.rsm.declaring_classes[key]
      field_mapping = class_metadata.field_mappings[field_name]
      owner_map = self.rsm.column_owner_map[key]

      column_info = ColumnInfo.new(
        field_name,
        Types::Type.get_type(field_mapping.type),
        owner_map,
        class_metadata.identifier.includes?(field_name)
      )

      # TODO: Handle discriminators

      return @cache[key] = column_info
    end

    nil
  end

  struct RowData
    getter data : Hash(String, Hash(String, Mapping::Value)) = Hash(String, Hash(String, Mapping::Value)).new { |hash, key| hash[key] = Hash(String, Mapping::Value).new }
    getter new_objects : Array(AORM::Entity) = [] of AORM::Entity
  end

  protected def gather_row_data(data : Hash, id : Hash(String, String), non_empty_component : Hash(String, Bool)) : RowData
    # TODO: Handle RSM new objects?
    # row_data = {
    #   data:        Hash(String, typeof(data)).new,
    #   new_objects: [] of AORM::Entity,
    # }
    row_data = RowData.new

    data.each do |key, value|
      next unless cache_key_info = self.hydrate_column_info key

      field_name = cache_key_info.field_name

      # TODO: Handle isNewObjectParamter
      # TODO: Handle isScalar

      alias_name = cache_key_info.alias_name
      type = cache_key_info.type

      # If there are field name collisions in the child class, then we need to only hydrate if we are looking at the correct discriminator value
      # TODO: Handle that

      # in an inheritance hierarchy the same field could be defined several times.
      # We overwrite this value so long we don't have a non-null value, that value we keep.
      # Per definition it cannot be that a field is defined several times and has several values.
      # TODO: Handle that

      row_data.data[alias_name][field_name] = Mapping::SingleValue.new type ? type.to_crystal_value(value, @platform) : value

      # TODO: Handle enum types

      if cache_key_info.is_identifier && !value.nil?
        id[alias_name] += "|#{value}"
        non_empty_component[alias_name] = true
      end
    end

    # TODO: Handle nested / new objects

    row_data
  end

  # Constructed manually with an explicit value type so Crystal does not infer
  # it from a `to_h` block before `lib/pg`'s array decoders finish registering.
  # The race produces a macro-expansion error in `array_decoder.cr`. This shape
  # is not related to `Mapping::Value` flow — `gather_row_data` is what wraps
  # the raw values; this method's job is just to normalize the read into a
  # column-keyed hash without snagging on PG decoder registration order.
  protected def fetch_assoc
    result = Hash(String, typeof(self.rs.read)).new
    self.rs.column_names.each { |col| result[col] = self.rs.read }
    result
  end

  protected def class_metadata(entity_class : AORM::Entity.class) : Mapping::ClassInterface
    @metadata_cache[entity_class] ||= @em.class_metadata entity_class
  end

  # Lifecycle hook called before hydration begins.
  protected def prepare : Nil
  end

  # Lifecycle hook called after hydration completes.
  protected def cleanup : Nil
    self.rs.close

    @rs = nil
    @rsm = nil
    @metadata_cache.clear
    @cache.clear

    # TODO: Remove onClear event listener
  end
end
