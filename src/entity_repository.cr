require "./repository_interface"

class Athena::ORM::EntityRepository(EntityType) < Athena::ORM::RepositoryInterface
  alias Criteria = Hash(String, DB::Any | Array(DB::Any))

  getter entity_class : AORM::Entity.class
  getter em : AORM::EntityManagerInterface
  getter class_metadata : AORM::Mapping::ClassInterface

  def initialize(@em : AORM::EntityManagerInterface, @class_metadata : AORM::Mapping::ClassInterface)
    @entity_class = @class_metadata.entity_class
  end

  def find(id : Hash(String, Int | String) | Int | String, lock_mode : AORM::LockMode? = nil, lock_version : Int32? = nil) : EntityType?
    @em.find(@entity_class, id, lock_mode, lock_version).as EntityType?
  end

  def find!(id : Hash(String, Int | String) | Int | String, lock_mode : AORM::LockMode? = nil, lock_version : Int32? = nil) : EntityType
    @em.find!(@entity_class, id, lock_mode, lock_version).as EntityType
  end

  def find_all : Array(EntityType)
    self.find_by Criteria.new
  end

  def find_by(**criteria : **T) : Array(EntityType) forall T
    {%
      entity_fields = EntityType.instance_vars.select(&.annotation(AORMA::Column)).map do |c|
        {name: c.name.id, type: c.type.resolve}
      end

      T.keys.each do |k|
        type = T[k]

        unless entity_field = entity_fields.find(&.["name"].==(k))
          k.raise "Unknown field '#{k}' for entity type #{EntityType}."
        end

        unless type <= entity_field["type"]
          k.raise "Expected '#{entity_field["type"]}' for field '#{k}', got '#{type}'."
        end
      end
    %}

    self.find_by criteria.to_h.transform_keys &.to_s
  end

  def find_by(criteria : Criteria = Criteria.new, order_by : Hash(String, String) = Hash(String, String).new, limit : Int? = nil, offset : Int? = nil) : Array(EntityType)
    persister = @em.unit_of_work.entity_persister @entity_class

    persister.load_all(criteria, order_by, limit, offset).map &.as EntityType
  end

  def find_one_by(**criteria : **T) : EntityType? forall T
    {%
      entity_fields = EntityType.instance_vars.select(&.annotation(AORMA::Column)).map do |c|
        {name: c.name.id, type: c.type.resolve}
      end

      T.keys.each do |k|
        type = T[k]

        unless entity_field = entity_fields.find(&.["name"].==(k))
          k.raise "Unknown field '#{k}' for entity type #{EntityType}."
        end

        unless type <= entity_field["type"]
          k.raise "Expected '#{entity_field["type"]}' for field '#{k}', got '#{type}'."
        end
      end
    %}

    self.find_one_by criteria.to_h.transform_keys &.to_s
  end

  def find_one_by(criteria : Criteria, order_by : Hash(String, String) = Hash(String, String).new) : EntityType?
    persister = @em.unit_of_work.entity_persister @entity_class

    persister.load(criteria, limit: 1, order_by: order_by).as EntityType?
  end

  def count : Int
    self.count Criteria.new
  end

  def count(**criteria : **T) : Int forall T
    {%
      entity_fields = EntityType.instance_vars.select(&.annotation(AORMA::Column)).map do |c|
        {name: c.name.id, type: c.type.resolve}
      end

      T.keys.each do |k|
        type = T[k]

        unless entity_field = entity_fields.find(&.["name"].==(k))
          k.raise "Unknown field '#{k}' for entity type #{EntityType}."
        end

        unless type <= entity_field["type"]
          k.raise "Expected '#{entity_field["type"]}' for field '#{k}', got '#{type}'."
        end
      end
    %}

    self.count criteria.to_h.transform_keys &.to_s
  end

  def count(criteria : Criteria) : Int
    @em.unit_of_work.entity_persister(@entity_class).count criteria
  end

  def inspect(io : IO) : Nil
    io << self.class
  end
end
