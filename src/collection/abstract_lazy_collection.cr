require "./collection"

abstract class Athena::ORM::AbstractLazyCollection(T)
  include Athena::ORM::Collection(T)
  include Indexable(T)

  # @collection : Athena::ORM::Collection
  @is_loaded : Bool = false

  def loaded? : Bool
    @is_loaded
  end

  def initialized=(value : Bool) : Bool
    @is_loaded = value
  end
end
