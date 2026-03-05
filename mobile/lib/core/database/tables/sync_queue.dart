import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Transactional outbox table for offline sync.
///
/// Every local mutation (CREATE/UPDATE/DELETE) atomically writes a row here
/// in the same Drift transaction as the entity write. The SyncEngine drains
/// this queue when connectivity is available, sending each item to the backend.
///
/// [id] is a client-generated UUID v4 — serves as idempotency key. The server
/// deduplicates by this key, so if the same item is pushed twice (e.g., after
/// a network failure mid-upload), the second push is a no-op.
///
/// [status] lifecycle: 'pending' → 'synced' (row deleted) or 'parked' (4xx error,
/// won't be retried automatically).
class SyncQueue extends Table {
  /// Client-generated UUID v4 — serves as the idempotency key for server-side dedup.
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// Entity type: 'company' | 'user' | 'user_role'
  TextColumn get entityType => text()();

  /// UUID of the entity being synced.
  TextColumn get entityId => text()();

  /// Operation type: 'CREATE' | 'UPDATE' | 'DELETE'
  TextColumn get operation => text()();

  /// JSON-encoded entity data for the sync payload.
  TextColumn get payload => text()();

  /// Sync status: 'pending' | 'synced' | 'parked'
  ///
  /// - pending: waiting to be sent
  /// - synced: successfully sent (row is deleted after confirmation)
  /// - parked: permanent failure (4xx), will not be retried automatically
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Number of upload attempts made for this item.
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  /// Last error message, set when marking as parked or on retry.
  TextColumn get errorMessage => text().nullable()();

  /// Timestamp when this queue entry was created — used for FIFO ordering.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
