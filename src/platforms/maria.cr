require "./platform"

# Base platform for MariaDB.
class Athena::ORM::Platforms::Maria < Athena::ORM::Platforms::AbstractMySQL
  def supports_returning? : Bool
    true
  end
end
