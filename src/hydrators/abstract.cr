abstract struct Athena::ORM::Hydrators::Abstract
  @em : AORM::EntityManagerInterface
  @platform : AORM::Platforms::Platform
  @uow : AORM::UnitOfWork

  # getter! result_set : DB::ResultSet

  def initialize(@em : AORM::EntityManagerInterface)
    @platform = @em.connection.database_platform
    @uow = @em.unit_of_work
  end

  # abstract def hydrate_all_data

  # abstract def hydrate_row_data

  def hydrate(result_set : DB::ResultSet, class_metadata : AORM::Mapping::ClassBase)
    # @result_set = result_set

    # self.prepare

    return unless (entity = class_metadata.entity_class.from_rs @em, class_metadata, result_set, @platform)

    # Check for associations
    class_metadata.each do |property|
      next unless property.is_a? AORM::Mapping::AssociationMetadata
      next if property.is_owning_side?

      assoc_class_metadata = @em.class_metadata property.target_entity
      assoc_property = assoc_class_metadata.property property.mapped_by.not_nil!

      settings = assoc_class_metadata.entity_class.from_rs @em, assoc_class_metadata, result_set, @platform

      property.set_value entity, settings
      assoc_property.not_nil!.set_value settings, entity
    end
    result_set.close

    @em.unit_of_work.manage_entity entity
  end

  # protected def prepare : Nil
  # end

  # protected def cleanup : Nil
  #   self.result_set.close
  # end
end
