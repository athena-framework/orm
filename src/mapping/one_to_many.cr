require "./to_many"

# Marker module for OneToMany associations.
module Athena::ORM::Mapping::OneToMany
  include Athena::ORM::Mapping::ToMany
end
