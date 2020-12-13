require "./interface"

class Athena::ORM::Sequencing::Planning::Noop
  include Athena::ORM::Sequencing::Planning::Interface

  def execute_immediate(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
  end

  def execute_deferred(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
  end

  def contains_deferred? : Bool
    false
  end
end
