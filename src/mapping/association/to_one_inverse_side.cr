abstract class Athena::ORM::Mapping::ToOneInverseSide < Athena::ORM::Mapping::InverseSide
  def self.new(mapping : Driver::ColumnMapping, name : String) : self
    instance = new mapping

    if instance.id
      raise "illegal inverse identifier association"
    end

    if instance.orphan_removal
      # TODO: Handle cascade remove

      instance = instance.copy_with unique: nil
    end

    instance
  end
end
