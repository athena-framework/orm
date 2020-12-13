class Athena::ORM::Mapping::ClassFactory
  record Context, metadata_factory : AORM::Mapping::ClassFactory, target_platform : AORM::Platforms::Platform

  @loaded_metadata = Hash(AORM::Entity.class, ClassBase).new

  getter target_platform : AORM::Platforms::Platform { @em.connection.database_platform }

  def initialize(@em : AORM::EntityManagerInterface); end

  def metadata(for entity : AORM::Entity.class) : AORM::Mapping::ClassBase
    if metadata = @loaded_metadata[entity]?
      return metadata
    end

    @loaded_metadata[entity] = entity.entity_metadata_class.build_metadata self.metadata_context
  end

  private def metadata_context : Context
    Context.new self, self.target_platform
  end
end
