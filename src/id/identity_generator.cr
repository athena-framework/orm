require "./abstract_generator"

class Athena::ORM::ID::IdentityGenerator < Athena::ORM::ID::AbstractGenerator
  # :inherit:
  def generate(em : AORM::EntityManagerInterface, entity : AORM::Entity? = nil)
    raise NotImplementedError.new "#{self.class} is not yet supported."
  end

  # :inherit:
  def post_insert? : Bool
    true
  end
end
