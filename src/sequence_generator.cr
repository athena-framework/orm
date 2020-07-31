require "./generator_interface"

struct Athena::ORM::SequenceGenerator
  include Athena::ORM::GeneratorInterface

  getter next_value : UInt64 = 0
  getter max_value : UInt64? = nil

  def initialize(@sequence_name : String, @allocation_size : UInt64); end

  def generate(em : AORM::EntityManagerInterface, entity : AORM::Entity? = nil) : UInt64 | String
    if @max_value.nil? || @max_value == @next_value
      connection = em.connection
      sql = connection.database_platform.sequence_next_val_sql @sequence_name

      p! sql
    end

    @next_value += 1
  end

  def post_insert_generator? : Bool
    false
  end
end
