# Persister for ManyToMany collections.
# Handles insert and delete operations on join tables.
class Athena::ORM::Persisters::Collection::ManyToManyPersister < Athena::ORM::Persisters::Collection::Abstract
  # Deletes all rows from the join table for this collection's owner.
  def delete(collection : AORM::PersistentCollection) : Nil
    mapping = collection.association
    return unless mapping.is_a?(AORM::Mapping::ManyToManyOwningSide)

    owner = collection.owner
    return unless owner

    sql = self.get_delete_sql(mapping)
    params = self.get_delete_sql_params(collection, mapping)

    @connection.exec sql, args: params
  end

  # Updates the join table by processing insert and delete diffs.
  def update(collection : AORM::PersistentCollection) : Nil
    mapping = collection.association
    return unless mapping.is_a?(AORM::Mapping::ManyToManyOwningSide)

    owner = collection.owner
    return unless owner

    delete_sql = self.get_delete_row_sql(mapping)
    insert_sql = self.get_insert_row_sql(mapping)

    # Delete removed elements
    collection.delete_diff.each do |element|
      next unless element.is_a?(AORM::Entity)
      params = self.get_delete_row_sql_params(collection, element, mapping)
      @connection.exec delete_sql, args: params
    end

    # Insert added elements
    collection.insert_diff.each do |element|
      next unless element.is_a?(AORM::Entity)
      params = self.get_insert_row_sql_params(collection, element, mapping)
      @connection.exec insert_sql, args: params
    end
  end

  # Generates SQL to delete all rows for an owner.
  protected def get_delete_sql(mapping : AORM::Mapping::ManyToManyOwningSide) : String
    join_table = mapping.join_table.not_nil!
    columns = mapping.relation_to_source_key_columns.keys

    "DELETE FROM #{join_table.name} WHERE #{columns.map { |c| "#{c} = ?" }.join(" AND ")}"
  end

  # Gets parameters for deleting all rows for an owner.
  protected def get_delete_sql_params(collection : AORM::PersistentCollection, mapping : AORM::Mapping::ManyToManyOwningSide) : Array(DB::Any)
    owner = collection.owner.not_nil!
    identifier = @uow.entity_identifier(owner)

    mapping.relation_to_source_key_columns.map do |join_col, ref_col|
      id_value = identifier[ref_col]?
      id_value.is_a?(AORM::Mapping::Value) ? id_value.value.as(DB::Any) : id_value.as(DB::Any)
    end
  end

  # Generates SQL to delete a single row.
  protected def get_delete_row_sql(mapping : AORM::Mapping::ManyToManyOwningSide) : String
    join_table = mapping.join_table.not_nil!
    source_columns = mapping.relation_to_source_key_columns.keys
    target_columns = mapping.relation_to_target_key_columns.keys
    all_columns = source_columns + target_columns

    "DELETE FROM #{join_table.name} WHERE #{all_columns.map { |c| "#{c} = ?" }.join(" AND ")}"
  end

  # Gets parameters for deleting a row.
  protected def get_delete_row_sql_params(collection : AORM::PersistentCollection, element : AORM::Entity, mapping : AORM::Mapping::ManyToManyOwningSide) : Array(DB::Any)
    self.collect_join_table_column_params(collection, element, mapping)
  end

  # Generates SQL to insert a single row.
  protected def get_insert_row_sql(mapping : AORM::Mapping::ManyToManyOwningSide) : String
    join_table = mapping.join_table.not_nil!
    source_columns = mapping.relation_to_source_key_columns.keys
    target_columns = mapping.relation_to_target_key_columns.keys
    all_columns = source_columns + target_columns
    placeholders = all_columns.map { "?" }.join(", ")

    "INSERT INTO #{join_table.name} (#{all_columns.join(", ")}) VALUES (#{placeholders})"
  end

  # Gets parameters for inserting a row.
  protected def get_insert_row_sql_params(collection : AORM::PersistentCollection, element : AORM::Entity, mapping : AORM::Mapping::ManyToManyOwningSide) : Array(DB::Any)
    self.collect_join_table_column_params(collection, element, mapping)
  end

  # Collects parameters for join table operations in column order.
  private def collect_join_table_column_params(collection : AORM::PersistentCollection, element : AORM::Entity, mapping : AORM::Mapping::ManyToManyOwningSide) : Array(DB::Any)
    owner = collection.owner.not_nil!

    owner_id = @uow.entity_identifier(owner)
    element_id = @uow.entity_identifier(element)

    params = [] of DB::Any

    # Source key columns (owner -> join table)
    mapping.relation_to_source_key_columns.each do |join_col, ref_col|
      id_value = owner_id[ref_col]?
      params << (id_value.is_a?(AORM::Mapping::Value) ? id_value.value.as(DB::Any) : id_value.as(DB::Any))
    end

    # Target key columns (join table -> element)
    mapping.relation_to_target_key_columns.each do |join_col, ref_col|
      id_value = element_id[ref_col]?
      params << (id_value.is_a?(AORM::Mapping::Value) ? id_value.value.as(DB::Any) : id_value.as(DB::Any))
    end

    params
  end
end
