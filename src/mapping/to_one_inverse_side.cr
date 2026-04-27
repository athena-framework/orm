abstract class Athena::ORM::Mapping::ToOneInverseSide < Athena::ORM::Mapping::InverseSide
  def self.new(mapping : Driver::ColumnMapping, name : String) : self
    if mapping.lazy_proxy
      raise "AORM::Proxy(T) is only valid on owning-side ToOne fields; field '#{mapping.field_name}' on '#{mapping.source_entity}' is the inverse side"
    end

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
