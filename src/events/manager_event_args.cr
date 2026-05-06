abstract class Athena::ORM::Events::ManagerEventArgs < Athena::ORM::Events::EventArgs
  getter entity_manager : AORM::EntityManagerInterface

  def initialize(
    @entity_manager : AORM::EntityManagerInterface,
  ); end
end
