require "./abstract_generator"

class Athena::ORM::ID::BigIntegerIdentityGenerator < Athena::ORM::ID::AbstractGenerator
  # :inherit:
  def generate(em : AORM::EntityManagerInterface, entity : AORM::Entity? = nil)
    0_i64
  end

  # :inherit:
  def post_insert? : Bool
    true
  end
end
