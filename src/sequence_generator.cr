require "./generator_interface"

struct Athena::ORM::SequenceGenerator
  include Athena::ORM::GeneratorInterface

  # TODO: Make these UInt64 to support UNSIGNED BIGINT
  getter next_value : Int64 = 0
  getter max_value : Int64? = nil

  def initialize(@sequence_name : String, @allocation_size : Int64); end

  def generate(em : AORM::EntityManagerInterface, entity : AORM::Entity? = nil)
    if @max_value.nil? || @max_value == @next_value
      connection = em.connection
      sql = connection.database_platform.sequence_next_val_sql @sequence_name

      @next_value = connection.scalar(sql).as(Int64)
      @max_value = @next_value + @allocation_size
    end

    value = @next_value

    @next_value += 1

    value
  end

  def post_insert_generator? : Bool
    false
  end
end
