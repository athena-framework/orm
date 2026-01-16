abstract struct Athena::ORM::Mapping::ToOneInverseSide < Athena::ORM::Mapping::InverseSide
  def self.new(mapping : Driver::ColumnMapping, name : String) : self
    mapping = new mapping

    if mapping.id
      raise "illegal inverse identifier association"
    end

    if mapping.orphan_removal
      # TODO: Handle cascade remove

      mapping = mapping.copy_with unique: nil
    end

    mapping
  end
end
