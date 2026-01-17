class Athena::ORM::Hydrators::SimpleObject < Athena::ORM::Hydrators::Abstract
  protected def hydrate_all_data : Array(AORM::Entity)
    result = [] of AORM::Entity

    self.rs.each do
      data = self.gather_row_data
      entity = @uow.create_entity(class_metadata, data, @hints)
      result << entity
      # TODO: Handle hints
    end

    result
  end

  # Reads column values from the result set in field definition order.
  # Crystal's DB::ResultSet.read reads columns sequentially, so we must
  # read them in the same order as they appear in the SELECT statement.
  private def gather_row_data : Hash(String, DB::Any?)
    data = {} of String => DB::Any?

    # Read columns in the order they appear in SELECT (field_names order)
    class_metadata.field_names.each_key do |column_name|
      if info = hydrate_column_info(column_name)
        # TODO: Handle Enums and maybe inheritance?
        data[info.field_name] = info.type.from_db(self.rs, @platform)
      end
    end

    data
  end
end
