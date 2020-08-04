module Athena::ORM::Mapping
  record JoinColumn, column_name : String, referenced_column_name : String, aliased_name : String? = nil, nilable : Bool = true, on_delete : String = "" do
    include Property

    protected def self.build_metadata(context : ClassFactory::Context, column_name : String) : self
      # TODO: Have a better way to resolve column names
      new "#{column_name}_id", "id"
    end

    def name
      "foo"
    end

    def value_generation_executor(platform : AORM::Platforms::Platform) : AORM::Sequencing::Executors::Interface?
    end
  end
end
