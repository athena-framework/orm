module Athena::ORM::ValueGenerationExecutorInterface
  abstract def execute(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
  abstract def deferred? : Bool
end
