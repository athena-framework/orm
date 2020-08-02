require "./repository_factory_interface"

struct Athena::ORM::DefaultRepositoryFactory
  include Athena::ORM::RepositoryFactoryInterface

  @repository_map = Hash(String, AORM::RepositoryInterface).new

  def repository(em : AORM::EntityManagerInterface, entity_class : AORM::Entity.class) : AORM::RepositoryInterface
    repo_hash = "#{entity_class}#{em.object_id}"

    if repo = @repository_map[repo_hash]?
      return repo
    end

    @repository_map[repo_hash] = create_repository em, entity_class
  end

  private def create_repository(em : AORM::EntityManagerInterface, entity_class : AORM::Entity.class) : AORM::RepositoryInterface
    class_metadata = entity_class.entity_class_metadata

    repo_class = class_metadata.custom_repository_class || class_metadata.default_repository_class

    repo_class.new em, class_metadata
  end
end
