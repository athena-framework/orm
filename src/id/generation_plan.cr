module Athena::ORM::Id
  module GenerationPlan
    abstract def execute_immediate(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
    abstract def execute_deferred(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
    abstract def contains_deferred? : Bool
  end

  class NoopPlan
    include GenerationPlan

    def execute_immediate(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
    end

    def execute_deferred(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
    end

    def contains_deferred? : Bool
      false
    end
  end

  struct SingleColumnPlan
    include GenerationPlan

    def initialize(
      @class_metadata : AORM::Mapping::ClassBase,
      @column_metadata : AORM::Mapping::ColumnMetadata,
      @generator : Generator
    ); end

    def execute_immediate(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
      unless @generator.post_insert?
        dispatch_generator em, entity
      end
    end

    def execute_deferred(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
      if @generator.post_insert?
        dispatch_generator em, entity
      end
    end

    def contains_deferred? : Bool
      @generator.post_insert?
    end

    private def dispatch_generator(em : AORM::EntityManagerInterface, entity : AORM::Entity) : Nil
      value = @generator.generate em, entity

      platform = em.connection.database_platform
      converted_value = @column_metadata.type.from_db value, platform

      column = @class_metadata.column(@column_metadata.column_name).not_nil!
      column.set_value entity, converted_value
    end
  end
end
