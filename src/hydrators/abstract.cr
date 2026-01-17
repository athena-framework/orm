abstract class Athena::ORM::Hydrators::Abstract
  # Column info cache structure
  private record ColumnInfo, type : AORM::Types::Type, field_name : String, identifier : Bool

  @em : AORM::EntityManagerInterface
  @platform : AORM::Platforms::Platform
  @uow : AORM::UnitOfWork

  # Column info cache
  @cache = Hash(String, ColumnInfo).new

  # Query hints
  @hints = Hash(String, String).new

  # Current result set being hydrated
  private getter! rs : DB::ResultSet

  # Current class metadata being hydrated
  private getter! class_metadata : AORM::Mapping::ClassInterface

  def initialize(@em : AORM::EntityManagerInterface)
    @platform = @em.connection.database_platform
    @uow = @em.unit_of_work
  end

  def hydrate_all(
    rs : DB::ResultSet,
    class_metadata : AORM::Mapping::ClassInterface,
    hints : Hash(String, String) = {} of String => String,
  ) : Array(AORM::Entity)
    @rs = rs
    @class_metadata = class_metadata
    @hints = hints

    # TODO: EM Eventing
    self.prepare

    begin
      self.hydrate_all_data
    ensure
      self.cleanup
    end
  end

  # Hydrates all rows from the current result set.
  # Children implement this with their specific hydration logic.
  protected abstract def hydrate_all_data : Array(AORM::Entity)

  # Retrieves column information with caching.
  protected def hydrate_column_info(column_name : String) : ColumnInfo?
    # TODO: Repalce this with `ResultSetMapping`?

    if ci = @cache[column_name]?
      return ci
    end

    return nil unless field_name = class_metadata.field_names[column_name]?
    return nil unless field = class_metadata.field_mappings[field_name]?

    @cache[column_name] = ColumnInfo.new(
      AORM::Types::Type.get_type(field.type),
      field_name,
      class_metadata.identifier.includes? field_name
    )
  end

  # Lifecycle hook called before hydration begins.
  protected def prepare : Nil
    @cache.clear
  end

  # Lifecycle hook called after hydration completes.
  protected def cleanup : Nil
    self.rs.close

    @rs = nil
    @class_metadata = nil
    @cache.clear
    @hints.clear
  end
end
