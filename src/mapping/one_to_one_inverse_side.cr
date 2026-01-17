require "./to_one_inverse_side"

class Athena::ORM::Mapping::OneToOneInverseSide < Athena::ORM::Mapping::ToOneInverseSide
  include Athena::ORM::Mapping::OneToOne
end
