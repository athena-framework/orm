class Athena::ORM::Internal::Hydrators::Object < Athena::ORM::Internal::Hydrators::Abstract
  protected def hydrate_all_data : Array
    raise NotImplementedError.new("ObjectHydrator not yet implemented")
  end
end
