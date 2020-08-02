class Athena::ORM::Persisters::Entity::CachedPersisterContext
  @sql_alias_counter = Int64.zero

  getter sql_table_aliases = Hash(String?, String).new
  getter class_metadata : AORM::Mapping::ClassBase
  getter handles_limit : Bool

  property select_column_list : String? = nil

  def initialize(@class_metadata : AORM::Mapping::ClassBase, @handles_limit : Bool); end

  def sql_alias_counter : Int
    idx = @sql_alias_counter
    @sql_alias_counter += 1
    idx
  end
end
