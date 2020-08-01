class Athena::ORM::CachedPersisterContext
  @sql_alias_counter = Int64.zero

  getter sql_table_aliases = Hash(String?, String).new
  getter class_metadata : AORM::Metadata::Class
  getter handles_limit : Bool

  property select_column_list : String? = nil

  def initialize(@class_metadata : AORM::Metadata::Class, @handles_limit : Bool); end

  def sql_alias_counter : Int
    idx = @sql_alias_counter
    @sql_alias_counter += 1
    idx
  end
end
