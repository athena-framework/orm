@[AORMA::Entity]
@[AORMA::Table(name: "countries")]
class Country < AORM::Entity
  @[AORMA::Column]
  @[AORMA::ID]
  @[AORMA::GeneratedValue(strategy: :none)]
  property! country : String
end
