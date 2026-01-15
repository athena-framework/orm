require "./abstract_generator"

class Athena::ORM::ID::IdentityGenerator < Athena::ORM::ID::AbstractGenerator
  # :inherit:
  def generate(em : AORM::EntityManagerInterface, entity : AORM::Entity? = nil)
    # TODO: How to make this platform agnostic?
    em.connection.scalar("SELECT LASTVAL()").as Int32
  end

  # :inherit:
  def post_insert? : Bool
    true
  end
end
