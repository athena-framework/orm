# Class metadata built by one entity manager, reused by others on the same database.
#
# Metadata depends on the database platform (e.g. which ID generator is used), so a cache must not be shared between databases.
class Athena::ORM::Mapping::MetadataCache
  @metadata = Hash(AORM::Entity.class, ClassInterface).new
  @mutex = Mutex.new

  def []?(entity_class : AORM::Entity.class) : ClassInterface?
    @mutex.synchronize { @metadata[entity_class]? }
  end

  def []=(entity_class : AORM::Entity.class, metadata : ClassInterface) : ClassInterface
    @mutex.synchronize { @metadata[entity_class] = metadata }
  end
end
