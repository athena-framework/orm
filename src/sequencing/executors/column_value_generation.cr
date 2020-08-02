require "./interface"

struct Athena::ORM::Sequencing::Executors::ColumnValueGeneration
  include Athena::ORM::Sequencing::Executors::Interface

  def initialize(@column_metadata : AORM::Mapping::ColumnBase, @generator : AORM::Sequencing::Generators::Interface); end

  def execute(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Tuple
    value = @generator.generate em, entity

    platform = em.connection.database_platform
    converted_value = @column_metadata.type.from_db value, platform

    {@column_metadata.column_name, converted_value}
  end

  def deferred? : Bool
    @generator.post_insert_generator?
  end
end
