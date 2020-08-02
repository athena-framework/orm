module Athena::ORM::Mapping
  record Table, name : String, schema : String? = nil do
    protected def self.build_metadata(context : ClassFactory::Context, entity_class : AORM::Entity.class, table : Annotations::Table?) : self
      new table.try &.name || entity_class.to_s.split("::").last.downcase + 's'
    end

    def quoted_qualified_name(platform : AORM::Platforms::Platform) : String
      unless @schema
        return platform.quote_identifier @name
      end

      seperator = !platform.supports_schemas? && platform.can_emulate_schemas? ? "__" : "."

      platform.quote_identifier "#{@schema}#{seperator}#{@name}"
    end
  end
end
