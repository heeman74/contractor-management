import '../sync/sync_queue_dao.dart';

/// Abstract interface for entity-specific sync handlers.
///
/// Each entity type (company, user, user_role) has its own [SyncHandler]
/// implementation registered in [SyncRegistry]. The [SyncEngine] delegates
/// to the appropriate handler for each outbox item.
///
/// Adding a new entity type requires only:
/// 1. Creating a class that extends [SyncHandler]
/// 2. Calling [SyncRegistry.register] with an instance of the new handler
///
/// This pattern avoids modifying [SyncEngine] when new entity types are added.
abstract class SyncHandler {
  /// The entity type string that identifies this handler in [SyncRegistry].
  ///
  /// Must match the [entityType] value stored in the sync_queue table.
  /// Examples: 'company', 'user', 'user_role'
  String get entityType;

  /// Push a pending outbox item to the backend.
  ///
  /// Called by [SyncEngine.drainQueue] for each pending [SyncQueueData] item.
  /// Implementations should POST/PUT/DELETE to the appropriate endpoint.
  /// The Idempotency-Key header must be set to [item.id] (UUID) to allow safe
  /// retries — the backend will deduplicate based on this key.
  ///
  /// Throws [DioException] on network/HTTP failure — [SyncEngine] uses the
  /// status code to decide whether to park (4xx) or retry (5xx/timeout).
  Future<void> push(SyncQueueData item);

  /// Apply a pulled entity from the backend delta response to local Drift DB.
  ///
  /// Called by [SyncEngine.pullDelta] for each entity in the sync response.
  /// Implementations must upsert the entity into the appropriate Drift table
  /// using [insertOnConflictUpdate] for idempotency.
  ///
  /// If [data] contains a non-null [deleted_at], the entity should be
  /// soft-deleted locally (tombstone propagation).
  Future<void> applyPulled(Map<String, dynamic> data);
}
