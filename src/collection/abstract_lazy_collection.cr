require "./collection"

abstract class Athena::ORM::AbstractLazyCollection(T)
  include Athena::ORM::Collection(T)
  include Indexable(T)

  # @collection : Athena::ORM::Collection
  property? initialized : Bool = false
end
