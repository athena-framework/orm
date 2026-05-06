class Athena::ORM::Events::LifecycleEventArgs(T) < Athena::ORM::Events::EventArgs
  getter entity : T
  getter entity_manager : AORM::EntityManagerInterface

  def initialize(
    @entity : T,
    @entity_manager : AORM::EntityManagerInterface,
  ); end
end
