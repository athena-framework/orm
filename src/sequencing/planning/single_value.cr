require "./interface"

class Athena::ORM::Sequencing::Planning::SingleValue
  include Athena::ORM::Sequencing::Planning::Interface

  def initialize(@class_metadata : AORM::Mapping::ClassBase, @executor : AORM::Sequencing::Executors::Interface); end

  def execute_immediate(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
    unless @executor.deferred?
      self.dispatch_executor em, entity
    end
  end

  def execute_deferred(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
    if @executor.deferred?
      self.dispatch_executor em, entity
    end
  end

  def contains_deferred? : Bool
    @executor.deferred?
  end

  private def dispatch_executor(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
    name, value = @executor.execute em, entity
    column = @class_metadata.column(name).not_nil!
    column.set_value entity, value
  end
end
