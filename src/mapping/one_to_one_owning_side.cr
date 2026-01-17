require "./to_one_owning_side"

class Athena::ORM::Mapping::OneToOneOwningSide < Athena::ORM::Mapping::ToOneOwningSide
  include Athena::ORM::Mapping::OneToOne
end
