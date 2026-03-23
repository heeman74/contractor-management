import 'package:drift/drift.dart';

/// AI message table — stores individual messages in an AI conversation.
///
/// Each row is one user or assistant turn in a conversation.
/// Messages are ordered by sequenceNum for correct playback.
class AiMessages extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text()();
  TextColumn get conversationId => text()();

  /// Role: 'user' | 'assistant'
  TextColumn get role => text()();

  /// Message content as JSON string (text blocks, tool use, etc.)
  TextColumn get contentJson => text()();

  IntColumn get sequenceNum => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
