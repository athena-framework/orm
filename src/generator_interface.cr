module Athena::ORM::GeneratorInterface
  abstract def generate(em : AORM::EntityManagerInterface, entity : AORM::Entity? = nil) : Int | String
  abstract def post_insert_generator? : Bool
end
