import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/ai_conversations.dart';
import '../../../core/database/tables/ai_messages.dart';

part 'ai_conversation_dao.g.dart';

/// DAO for AI conversation transcript cache (D-31).
///
/// Provides read/write access to locally cached AI conversation data.
/// Used to display conversation history when offline after initial completion.
@DriftAccessor(tables: [AiConversations, AiMessages])
class AiConversationDao extends DatabaseAccessor<AppDatabase>
    with _$AiConversationDaoMixin {
  AiConversationDao(super.db);

  /// Upsert a conversation record.
  ///
  /// Inserts a new row or replaces the existing one if the id already exists.
  Future<void> upsertConversation(AiConversationsCompanion conversation) async {
    await into(aiConversations).insertOnConflictUpdate(conversation);
  }

  /// Batch upsert messages for a conversation.
  ///
  /// Inserts or updates each message, ordered by sequenceNum.
  Future<void> upsertMessages(List<AiMessagesCompanion> messages) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(aiMessages, messages);
    });
  }

  /// Watch messages for a conversation ordered by sequence number.
  ///
  /// Returns a stream that emits whenever any message in the conversation changes.
  Stream<List<AiMessage>> watchMessagesByConversation(String conversationId) {
    return (select(aiMessages)
          ..where((m) => m.conversationId.equals(conversationId))
          ..where((m) => m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm.asc(m.sequenceNum)]))
        .watch();
  }

  /// Get active conversation for a project and conversation type.
  ///
  /// Returns null if no active conversation exists for the given project + type.
  Future<AiConversation?> getActiveForProject(
    String projectId,
    String convType,
  ) async {
    return (select(aiConversations)
          ..where((c) => c.projectId.equals(projectId))
          ..where((c) => c.convType.equals(convType))
          ..where((c) => c.status.equals('active'))
          ..where((c) => c.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// Get active conversation for a trade scope.
  ///
  /// Returns null if no active interview conversation exists for the scope.
  Future<AiConversation?> getActiveForScope(String scopeId) async {
    return (select(aiConversations)
          ..where((c) => c.scopeId.equals(scopeId))
          ..where((c) => c.convType.equals('interview'))
          ..where((c) => c.status.equals('active'))
          ..where((c) => c.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }
}
