import 'package:drift/drift.dart';

import 'companies.dart';

/// AI conversation table — caches transcript metadata locally for offline viewing.
///
/// Stores one row per conversation session (intake or interview).
/// The full message transcript is stored in ai_messages table.
/// This table is populated after conversation completion (D-31).
class AiConversations extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get projectId => text().nullable()();
  TextColumn get scopeId => text().nullable()();
  TextColumn get userId => text()();

  /// Conversation type: 'intake' | 'interview'
  TextColumn get convType => text()();

  /// Status: 'active' | 'completed' | 'abandoned'
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// Cached transcript JSON (array of message objects for fast re-rendering)
  TextColumn get transcriptJson => text().withDefault(const Constant('[]'))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
