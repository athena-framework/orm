require "./naming_strategy_interface"

struct Athena::ORM::Mapping::DefaultNamingStrategy
  include Athena::ORM::Mapping::NamingStrategyInterface

  def property_to_column_name(property_name : String, entity_class : AORM::Entity.class) : String
    property_name
  end

  def reference_column_name : String
    "id"
  end

  def join_column_name(property_name : String, entity_class : AORM::Entity.class) : String
    "#{property_name}_#{self.reference_column_name}"
  end
end
