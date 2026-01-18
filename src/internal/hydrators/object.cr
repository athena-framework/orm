class Athena::ORM::Internal::Hydrators::Object < Athena::ORM::Internal::Hydrators::Abstract
  # TODO: Implement for associations/joins when needed
  protected def hydrate_all_data : Array(AORM::Entity)
    raise NotImplementedError.new("ObjectHydrator not yet implemented - use SimpleObjectHydrator")
  end
end
