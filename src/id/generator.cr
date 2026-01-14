module Athena::ORM::Id
  module Generator
    abstract def generate(em : AORM::EntityManagerInterface, entity : AORM::Entity? = nil)
    abstract def post_insert? : Bool
  end
end
