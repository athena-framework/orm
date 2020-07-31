module Athena::ORM::ValueGenerationExecutorInterface
  abstract def execute(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Tuple
  abstract def deferred? : Bool
end
