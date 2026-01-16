module Athena::ORM::Mapping::NamingStrategyInterface
  # abstract def class_to_table_name(entity_class : AORM::Entity.class) : String
  abstract def property_to_column_name(property_name : String, entity_class : AORM::Entity.class) : String

  # abstract def embedded_field_to_column_name(property_name : String, embedded_column_name : String, entity_class : AORM::Entity.class, embedded_entity_class : AORM::Entity.class) : String

  abstract def reference_column_name : String

  # abstract def join_table_name(source_entity : AORM::Entity.class, target_entity : AORM::Entity.class, property_name : String) : String
  abstract def join_column_name(property_name : String, entity_class : AORM::Entity.class) : String
  # abstract def join_key_column_name(entity_class : AORM::Entity.class, referenced_column_name : String?) : String
end
