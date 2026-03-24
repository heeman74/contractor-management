import 'package:drift/drift.dart';

/// Drift table definition for ChatThread entities.
///
/// A ChatThread is a persistent conversation channel scoped to a project.
/// Thread type determines whether the thread covers an entire project
/// ('project_wide') or is scoped to a specific trade scope ('scope').
///
/// [unreadCount] and [lastMessageAt] are local-only computed fields
/// updated by the chat sync service after each incoming message batch.
/// They are NOT persisted to the backend.
///
/// Offline-first: threads are seeded from the API on first open and
/// updated via WebSocket events and periodic REST sync.
class ChatThreads extends Table {
  /// UUID matching backend chat_threads.id.
  TextColumn get id => text()();

  /// Tenant scope — matches JWT companyId.
  TextColumn get companyId => text()();

  /// FK to projects.id — soft reference (no hard Drift FK).
  TextColumn get projectId => text()();

  /// Thread classification: 'scope' or 'project_wide'.
  TextColumn get threadType => text()();

  /// FK to trade_scopes.id — non-null only when threadType == 'scope'.
  TextColumn get tradeScopeId => text().nullable()();

  /// Display name for the thread (e.g., trade scope name or "Project Wide").
  TextColumn get name => text()();

  /// Local-only count of unread messages for the current user.
  /// Updated by ChatSyncService when read receipts arrive.
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  /// Local-only timestamp of the most recent message — used for sorting.
  /// Updated by ChatSyncService when messages arrive.
  DateTimeColumn get lastMessageAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
