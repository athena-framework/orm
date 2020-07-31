module Athena::ORM::ValueGenerationPlanInterface
  abstract def execute_immediate(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
  abstract def execute_deferred(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
  abstract def contains_deferred? : Bool
end
