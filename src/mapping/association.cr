# Require all association mapping types in dependency order.

require "./association/association"
require "./association/join_column"
require "./association/to_one"
require "./association/one_to_one"
require "./association/inverse_side"
require "./association/owning_side"
require "./association/to_one_inverse_side"
require "./association/to_one_owning_side"
require "./association/one_to_one_inverse_side"
require "./association/one_to_one_owning_side"

module Athena::ORM::Mapping
  # Backward compatibility module used by unit_of_work.cr
  module AssociationMetadataBase
  end
end
