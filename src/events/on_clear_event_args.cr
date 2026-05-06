class Athena::ORM::Events::OnClearEventArgs < Athena::ORM::Events::EventArgs
  getter entity_manager : AORM::EntityManagerInterface

  def initialize(
    @entity_manager : AORM::EntityManagerInterface,
  ); end
end
