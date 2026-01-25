class Athena::ORM::Internal::Hydrators::SimpleObject < Athena::ORM::Internal::Hydrators::Abstract
  private getter! class_metadata : Mapping::ClassInterface

  protected def prepare : Nil
    raise "Cannot use SimpleObject with an RSM that contains more than one object result" if self.rsm.alias_map.size != 1
    raise "Cannot use SimpleObject Hydrator with a RSM that contains scalar mappings" unless self.rsm.scalar_mappings.empty?

    @class_metadata = self.class_metadata(self.rsm.alias_map.first_value)
  end

  protected def hydrate_all_data : Array(AORM::Entity)
    result = [] of AORM::Entity

    self.rs.each do
      # Gather row data as a has to make things simpler?
      # TODO: See if we could just pass in the RS instead maybe?
      row_data = self.fetch_assoc

      self.hydrate_row_data row_data, result
    end

    # TODO: Trigger eager loads

    result
  end

  protected def hydrate_row_data(row_data : Hash, result : Array(AORM::Entity)) : Nil
    # pp row_data

    entity_class = self.class_metadata.entity_class
    data = row_data.class.new

    # TODO: Handle discriminator mappings
    unless self.class_metadata.inheritance_type.none?
      raise "TODO: Handle discriminator mappings"
    end

    row_data.each do |column, value|
      if self.rsm.relation_map.has_key? column
        raise "Unable to retrieve association information for column '#{column}."
      end

      next unless cache_key_info = self.hydrate_column_info column

      # TODO: Handle discriminator values

      value_is_nil = value.nil?

      type = nil
      if t = cache_key_info.type
        type = t
        value = t.to_crystal_value value, @platform
      end

      # TODO: Handle enum types

      field_name = cache_key_info.field_name

      # Prevent overwrite in case of inherit classes using same property name (See AbstractHydrator)
      if !data.has_key?(field_name) && !value_is_nil
        data[field_name] = value
      end
    end

    # TODO: handle refresh hint

    uow = @em.unit_of_work
    entity = uow.create_entity entity_class, data, @hints

    result << entity

    # TODO: handle internal iteration hint
  end

  protected def cleanup : Nil
    super

    # TODO: Trigger eager loads
  end
end
