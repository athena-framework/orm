struct Athena::ORM::ID::AssignedGenerator < Athena::ORM::ID::AbstractGenerator
  # :inherit:
  def generate(em : AORM::EntityManagerInterface, entity : AORM::Entity? = nil)
    nil
  end
end
