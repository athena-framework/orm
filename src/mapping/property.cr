module Athena::ORM::Mapping::Property
  # def set_value(entity : AORM::Entity, value : _) : Nil
  # end

  # def get_value(entity : AORM::Entity)
  #   raise "BUG: Invoked default get_value"
  # end

  abstract def get_value(entity : AORM::Entity)
  abstract def set_value(entity : AORM::Entity, value : _)
  abstract def name : String
  abstract def is_primary_key? : Bool
  abstract def has_value_generator? : Bool
  abstract def value_generator : AORM::Mapping::ValueGeneratorMetadata?
end
