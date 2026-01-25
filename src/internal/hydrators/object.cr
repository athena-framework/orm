class Athena::ORM::Internal::Hydrators::Object < Athena::ORM::Internal::Hydrators::Abstract
  @identifier_map = Hash(String, Hash(String, Int32)).new do |hash, key|
    hash[key] = Hash(String, Int32).new
  end

  @result_pointers = {} of String => AORM::Entity
  @id_template = Hash(String, String).new
  @root_aliases = Hash(String, Bool).new
  @result_counter : Int32 = 0

  protected def prepare : Nil
    if !@hints.defer_eager_load?
      @hints.defer_eager_load = true
    end

    self.rsm.alias_map.each do |alias_name, entity_class|
      @id_template[alias_name] = ""

      # Remember which associations are "fetch joined", so that we know where to inject collection stubs or proxies and where not.
      next unless self.rsm.relation_map.has_key? alias_name

      parent = self.rsm.parent_alias_map[alias_name]

      unless self.rsm.alias_map.has_key? parent
        # TODO: Skip nested entities

        raise "parent object of relation not found"
      end

      source_entity_class = self.rsm.alias_map[parent]
      source_class_metadata = self.class_metadata source_entity_class
      assoc = source_class_metadata.association_mappings[self.rsm.relation_map[alias_name]]

      raise "TODO"
    end
  end

  protected def cleanup : Nil
    eager_load = @hints.defer_eager_load? == true

    super

    @identifier_map.clear

    if eager_load
      @uow.trigger_eager_loads
    end

    # TODO: Hydration complete trigger
  end

  protected def hydrate_all_data : Array
    result = [] of AORM::Entity

    self.rs.each do
      # Gather row data as a has to make things simpler?
      # TODO: See if we could just pass in the RS instead maybe?
      row_data = self.fetch_assoc

      self.hydrate_row_data row_data, result
    end

    # Snapshot newly initialized collections

    result
  end

  protected def hydrate_row_data(row : Hash, result : Array(AORM::Entity)) : Nil
    id = @id_template
    non_empty_components = Hash(String, Bool).new
    # Split the row data into chunks of class data;
    row_data = self.gather_row_data row, id, non_empty_components

    @result_pointers.clear

    result_key = nil

    # Hydrate data chunks
    row_data.data.each do |alias_name, data|
      entity_class = self.rsm.alias_map[alias_name]

      # TODO: Handle parent joins
      if false
      else
        # Root entity
        @root_aliases[alias_name] = true
        entity_key = self.rsm.entity_mappings[alias_name]? || 0

        # If this row has a nil value for the root result id, then we make it a null result
        # TODO: Handle this

        if !@identifier_map.has_key?(alias_name) || !@identifier_map[alias_name].has_key?(id[alias_name])
          element = self.entity data, alias_name

          # TODO: Handle mixed elements

          if false
            # TODO: Handle indexed alias
          else
            result_key = @result_counter
            @result_counter += 1

            if collection = @hints.collection?
              collection.hydrate_add element
            end

            result << element
          end

          @identifier_map[alias_name][id[alias_name]] = result_key.not_nil!

          @result_pointers[alias_name] = element
        else
          raise "Update result ptr"
        end
      end
    end

    if result_key.nil?
      @result_counter += 1
    end

    # TODO: Handle scalars

    # TODO: Handle new objects
  end

  private def entity(data : Hash, alias_name : String) : AORM::Entity
    entity_class = self.rsm.alias_map[alias_name]

    # TODO: Handle discriminator maps

    # TODO: Handle refresh entity hint

    @hints.fetch_alias = alias_name

    @uow.create_entity entity_class, data, @hints
  end
end
