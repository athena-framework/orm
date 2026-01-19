@[AORMA::Entity]
@[AORMA::Table(name: "cms_users")]
class CmsUser < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue]
  property! id : Int32

  @[AORMA::Column(length: 50)]
  property! username : String

  @[AORMA::ManyToMany(target_entity: CmsGroup, inversed_by: "users", cascade: ["persist"])]
  property groups : AORM::PersistentCollection(CmsGroup) = AORM::PersistentCollection(CmsGroup).new
end
