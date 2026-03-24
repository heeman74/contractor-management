import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../../core/auth/token_storage.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';
import '../data/chat_repository.dart';
import '../data/chat_sync_service.dart';
import '../data/chat_ws_client.dart';

/// Base WebSocket URL derived from the HTTP base URL.
///
/// Converts 'http://...' → 'ws://...' and strips '/api/v1' path suffix.
const _baseWsUrl = String.fromEnvironment(
  'BASE_WS_URL',
  defaultValue: 'ws://localhost:8000',
);

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

/// Provides [ChatDao] from the singleton [AppDatabase] in GetIt.
final chatDaoProvider = Provider<ChatDao>((ref) {
  return GetIt.instance<AppDatabase>().chatDao;
});

/// Provides [ChatRepository] wired to Dio from GetIt and the local ChatDao.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final dao = ref.watch(chatDaoProvider);
  return ChatRepository(
    dio: GetIt.instance<DioClient>().instance,
    chatDao: dao,
  );
});

/// Provides [ChatSyncService] wired to AppDatabase and ChatDao.
final chatSyncServiceProvider = Provider<ChatSyncService>((ref) {
  final db = GetIt.instance<AppDatabase>();
  final dao = ref.watch(chatDaoProvider);
  return ChatSyncService(db: db, chatDao: dao);
});

// ---------------------------------------------------------------------------
// WebSocket client provider (per-thread, auto-disposed)
// ---------------------------------------------------------------------------

/// Creates a [ChatWsClient] for a specific thread, auto-disposed on leave.
///
/// The provider family key is the threadId. Riverpod's autoDispose ensures
/// the WebSocket is closed when the thread screen is not visible.
final chatWsClientProvider =
    Provider.autoDispose.family<ChatWsClient, String>((ref, threadId) {
  final tokenStorage = GetIt.instance<TokenStorage>();

  final client = ChatWsClient(
    baseWsUrl: _baseWsUrl,
    tokenProvider: () async {
      final token = await tokenStorage.readAccessToken();
      if (token == null) {
        throw StateError('No access token available for WebSocket auth');
      }
      return token;
    },
  );

  // Connect to the thread immediately and register disposal.
  // ignore: cascade_invocations
  client.connect(threadId);
  ref.onDispose(client.dispose);

  return client;
});

// ---------------------------------------------------------------------------
// Reactive data providers (per-thread / per-project, auto-disposed)
// ---------------------------------------------------------------------------

/// Stream of chat messages for a thread, ordered by seq ASC.
///
/// Uses Drift's reactive watch — emits new lists whenever local DB changes.
/// Auto-disposed when the thread screen leaves the widget tree.
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, threadId) {
  final dao = ref.watch(chatDaoProvider);
  return dao.watchMessages(threadId);
});

/// Stream of chat threads for a project, ordered by lastMessageAt DESC.
///
/// Auto-disposed when the project chat list screen leaves the widget tree.
final chatThreadsProvider = StreamProvider.autoDispose
    .family<List<ChatThread>, String>((ref, projectId) {
  final dao = ref.watch(chatDaoProvider);
  return dao.watchThreadsByProject(projectId);
});
