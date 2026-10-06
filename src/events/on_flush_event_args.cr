# Emitted by `AORM::EntityManager#flush` once the changes to every managed entity have been computed, before anything is written.
#
# Listeners can inspect what the flush is about to do through the unit of work:
#
# ```
# dispatcher = AED::EventDispatcher.new
#
# dispatcher.listener AORM::Events::OnFlushEventArgs do |event|
#   uow = event.entity_manager.unit_of_work
#
#   uow.scheduled_entity_insertions.each { |entity| Log.info { "Inserting #{entity.class}" } }
#   uow.scheduled_entity_updates.each { |entity| Log.info { "Updating #{entity.class}: #{uow.entity_changeset(entity).keys}" } }
#   uow.scheduled_entity_deletions.each { |entity| Log.info { "Deleting #{entity.class}" } }
# end
#
# em = AORM::EntityManager.new connection, dispatcher
# ```
#
# It's emitted on every flush, even when there is nothing to write.
# Only the event dispatcher receives it; there is no lifecycle callback for it.
#
# TODO: Change sets can't be recomputed through the public API yet, so changes made to entities, or new entities persisted, in an `OnFlush` listener aren't guaranteed to be written.
class Athena::ORM::Events::OnFlushEventArgs < Athena::ORM::Events::ManagerEventArgs; end
