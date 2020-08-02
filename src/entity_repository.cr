class Athena::ORM::EntityRepository
  include Athena::ORM::RepositoryInterface

  getter entity_class : AORM::Entity.class
  getter em : AORM::EntityManagerInterface
  getter class_metadata : AORM::Metadata::Class

  def initialize(@em : AORM::EntityManagerInterface, @class_metadata : AORM::Metadata::Class)
    @entity_class = @class_metadata.entity_class
  end

  def clear : Nil
    @em.clear
  end

  def find(id : Hash(String, Int | String) | Int | String, lock_mode : AORM::LockMode? = nil, lock_version : Int32? = nil) : AORM::Entity?
    @em.find @entity_class, id, lock_mode, lock_version
  end

  def find_all : Array(AORM::Entity)
    self.find_by Hash(String, DB::Any).new
  end

  def find_by(**criteria) : Array(ORM::Entity)
    self.find_by criteria.to_h.transform_keys &.to_s
  end

  def find_by(criteria : Hash(String, DB::Any), order_by : Array(String) = [] of String, limit : Int? = nil, offset : Int? = nil) : Array(ORM::Entity)
    persister = @em.unit_of_work.entity_persister @entity_class

    persister.load_all criteria, order_by, limit, offset
  end

  def find_one_by(**criteria) : AORM::Entity?
    self.find_one_by criteria.to_h.transform_keys &.to_s
  end

  def find_one_by(criteria : Hash(String, DB::Any), order_by : Array(String) = [] of String) : AORM::Entity?
    persister = @em.unit_of_work.entity_persister @entity_class

    persister.load criteria, limit: 1, order_by: order_by
  end

  def count(**criteria) : Int
    self.count criteria.to_h.transform_keys &.to_s
  end

  def count(criteria : Hash(String, DB::Any)) : Int
    @em.unit_of_work.entity_persister(@entity_class).count criteria
  end
end
