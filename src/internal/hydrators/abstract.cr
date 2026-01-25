class Athena::ORM::Query::Hints
end

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

  protected def gather_row_data : Hash
    self.rs.column_names.to_h do |col|
      {col, self.rs.read}
    end
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
