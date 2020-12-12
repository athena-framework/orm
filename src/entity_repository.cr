require "./repository_interface"

class Athena::ORM::EntityRepository(EntityType) < Athena::ORM::RepositoryInterface
  getter entity_class : AORM::Entity.class
  getter em : AORM::EntityManagerInterface
  getter class_metadata : AORM::Mapping::ClassBase

  def initialize(@em : AORM::EntityManagerInterface, @class_metadata : AORM::Mapping::ClassBase)
    @entity_class = @class_metadata.entity_class
  end

  def clear : Nil
    @em.clear
  end

  def find(id : Hash(String, Int | String) | Int | String, lock_mode : AORM::LockMode? = nil, lock_version : Int32? = nil) : EntityType?
    @em.find(@entity_class, id, lock_mode, lock_version).as EntityType
  end

  def find!(id : Hash(String, Int | String) | Int | String, lock_mode : AORM::LockMode? = nil, lock_version : Int32? = nil) : EntityType
    @em.find!(@entity_class, id, lock_mode, lock_version)
  end

  def find_all : Array(EntityType)
    self.find_by Hash(String, DB::Any | Array(DB::Any)).new
  end

  def find_by(**criteria) : Array(EntityType)
    self.find_by criteria.to_h.transform_keys &.to_s
  end

  def find_by(criteria : Hash(String, DB::Any | Array(DB::Any)), order_by : Array(String) = [] of String, limit : Int? = nil, offset : Int? = nil) : Array(EntityType)
    persister = @em.unit_of_work.entity_persister @entity_class

    persister.load_all(criteria, order_by, limit, offset).map &.as EntityType
  end

  def find_one_by(**criteria) : EntityType?
    self.find_one_by criteria.to_h.transform_keys &.to_s
  end

  def find_one_by(criteria : Hash(String, DB::Any | Array(DB::Any)), order_by : Array(String) = [] of String) : EntityType?
    persister = @em.unit_of_work.entity_persister @entity_class

    persister.load(criteria, limit: 1, order_by: order_by).as EntityType?
  end

  def count(**criteria) : Int
    self.count criteria.to_h.transform_keys &.to_s
  end

  def count(criteria : Hash(String, DB::Any | Array(DB::Any))) : Int
    @em.unit_of_work.entity_persister(@entity_class).count criteria
  end
end
