# Holds the map of all known ORM types, keyed by name.
struct Athena::ORM::Types::TypeRegistry
  @instances = Hash(::String, AORM::Types::Type).new

  def initialize(instances : Hash(::String, AORM::Types::Type) = {} of ::String => AORM::Types::Type)
    instances.each do |name, type|
      register(name, type)
    end
  end

  def get(name : ::String) : AORM::Types::Type
    @instances[name]? || raise "Unknown type: #{name}"
  end

  def has?(name : ::String) : Bool
    @instances.has_key?(name)
  end

  def register(name : ::String, type : AORM::Types::Type) : Nil
    raise "Type '#{name}' already exists" if @instances.has_key?(name)
    @instances[name] = type
  end

  def override(name : ::String, type : AORM::Types::Type) : Nil
    raise "Type '#{name}' not found" unless @instances.has_key?(name)
    @instances[name] = type
  end
end
