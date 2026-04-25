require "./orm_exception"

class Athena::ORM::Exceptions::MissingIdentifierField < Athena::ORM::Exceptions::ORMException
  def initialize(entity_class : AORM::Entity.class, missing : Enumerable(String))
    super "Missing identifier field(s) for '#{entity_class}': #{missing.join(", ")}"
  end

  def initialize(entity_class : AORM::Entity.class, message : String)
    super "Identifier mismatch for '#{entity_class}': #{message}"
  end
end
