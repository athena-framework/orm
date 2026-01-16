abstract struct Athena::ORM::Mapping::ToOneOwningSide < Athena::ORM::Mapping::OwningSide
  include Athena::ORM::Mapping::ToOne

  @source_to_target_key_columns : Hash(String, String) = {} of String => String
  @target_to_source_key_columns : Hash(String, String) = {} of String => String

  @join_columns : Array(JoinColumn) = [] of JoinColumn
  @join_column_field_names : Hash(String, String) = {} of String => String
end
