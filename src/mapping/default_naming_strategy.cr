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

  def join_table_name(source_entity : String, target_entity : String, property_name : String?) : String
    "#{source_entity.underscore}_#{target_entity.underscore}"
  end

  def join_key_column_name(entity_name : String, referenced_column_name : String?) : String
    suffix = referenced_column_name || self.reference_column_name
    "#{entity_name.underscore}_#{suffix}"
  end
end
