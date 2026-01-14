require "./generator"

struct Athena::ORM::Id::IdentityGenerator
  include Athena::ORM::Id::Generator

  def generate(em : AORM::EntityManagerInterface, entity : AORM::Entity? = nil)
    # Identity columns are populated by the database after INSERT
    # The actual value retrieval happens in execute_deferred via LAST_INSERT_ID or RETURNING
    raise "BUG: IdentityGenerator.generate should not be called directly"
  end

  def post_insert? : Bool
    true
  end
end
