require "./to_many"

# Marker module for ManyToMany associations.
module Athena::ORM::Mapping::ManyToMany
  include Athena::ORM::Mapping::ToMany
end
