class Athena::ORM::Schema::Column
  getter name : String
  getter type : Types::Type

  property length : Int32? = nil
  property? fixed : Bool = false
  property? auto_increment : Bool = false
  property? unsigned : Bool = false

  def initialize(
    @name : String,
    @type : Types::Type,
  ); end
end
