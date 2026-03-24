import 'package:flutter_riverpod/flutter_riverpod.dart';

// app_database.dart exports ProjectDao, TradeScopeDao, TaskDao, TaskNoteDao,
// TaskAttachmentDao, and data classes (Project, TradeScope, ProjectTask,
// TaskNote, TaskAttachment) via its re-export declarations.
// UserRole is also re-exported; we hide it to use the canonical shared model.
import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../core/di/service_locator.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/models/user_role.dart';

/// Provider exposing the [ProjectDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [ProjectDao] is a database accessor
/// registered at startup in service_locator.dart. Riverpod providers that
/// need the DAO read it via this provider — dependency is explicit and
/// testable via ProviderScope overrides.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final projectDaoProvider = Provider<ProjectDao>((ref) {
  return getIt<ProjectDao>();
});

/// Provider exposing the [TradeScopeDao] singleton from GetIt.
final tradeScopeDaoProvider = Provider<TradeScopeDao>((ref) {
  return getIt<TradeScopeDao>();
});

/// Provider exposing the [TaskDao] singleton from GetIt.
final taskDaoProvider = Provider<TaskDao>((ref) {
  return getIt<TaskDao>();
});

/// Provider exposing the [TaskNoteDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [TaskNoteDao] is a database accessor
/// registered at startup in service_locator.dart. Riverpod providers that
/// need the DAO read it via this provider — dependency is explicit and
/// testable via ProviderScope overrides.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final taskNoteDaoProvider = Provider<TaskNoteDao>((ref) {
  return getIt<TaskNoteDao>();
});

/// Provider exposing the [TaskAttachmentDao] singleton from GetIt.
///
/// NOTE: Same GetIt<->Riverpod tradeoff as taskNoteDaoProvider.
final taskAttachmentDaoProvider = Provider<TaskAttachmentDao>((ref) {
  return getIt<TaskAttachmentDao>();
});

// ────────────────────────────────────────────────────────────────────────────
// Project list — role-aware stream
// ────────────────────────────────────────────────────────────────────────────

/// Streams all projects visible to the current user.
///
/// Role-aware:
/// - GC/admin role: watches ALL projects for the company
///   via [ProjectDao.watchProjectsByCompany].
/// - Contractor role: watches ONLY projects where the contractor has an
///   assigned trade scope via [ProjectDao.watchProjectsForContractor].
///   This enforces role-based data access at the DAO level.
///
/// Uses [AsyncNotifier] because [build()] must await the auth state
/// before setting up the stream subscription.
class ProjectListNotifier extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() async {
    final authState = ref.watch(authNotifierProvider);

    if (authState is! AuthAuthenticated) {
      return [];
    }

    final dao = ref.watch(projectDaoProvider);
    final companyId = authState.companyId;
    final userId = authState.userId;

    // Contractor role: only projects with assigned scope
    final isContractorOnly = authState.roles.contains(UserRole.contractor) &&
        !authState.roles.contains(UserRole.admin);

    final stream = isContractorOnly
        ? dao.watchProjectsForContractor(companyId, userId)
        : dao.watchProjectsByCompany(companyId);

    final sub = stream.listen(
      (projects) => state = AsyncData(projects),
      onError: (Object e, StackTrace st) => state = AsyncError(e, st),
    );
    ref.onDispose(sub.cancel);

    return await stream.first;
  }
}

/// Provider for [ProjectListNotifier].
final projectListProvider =
    AsyncNotifierProvider<ProjectListNotifier, List<Project>>(
  ProjectListNotifier.new,
);

// ────────────────────────────────────────────────────────────────────────────
// Trade scopes for a project — family provider parameterized by projectId
// ────────────────────────────────────────────────────────────────────────────

/// Streams all active trade scopes for a given project.
///
/// StreamProvider.family — one instance per projectId. Auto-disposed
/// when the project detail screen is popped.
final tradeScopesProvider = StreamProvider.autoDispose
    .family<List<TradeScope>, String>((ref, projectId) {
  final dao = ref.watch(tradeScopeDaoProvider);
  return dao.watchScopesByProject(projectId);
});

// ────────────────────────────────────────────────────────────────────────────
// Tasks for a trade scope — family provider parameterized by tradeScopeId
// ────────────────────────────────────────────────────────────────────────────

/// Streams all active tasks for a given trade scope.
///
/// StreamProvider.family — one instance per tradeScopeId. Auto-disposed
/// when the scope detail screen is popped.
final tasksProvider = StreamProvider.autoDispose
    .family<List<ProjectTask>, String>((ref, tradeScopeId) {
  final dao = ref.watch(taskDaoProvider);
  return dao.watchTasksByScope(tradeScopeId);
});

// ────────────────────────────────────────────────────────────────────────────
// Contractor cross-scope task query — "My Tasks" view
// ────────────────────────────────────────────────────────────────────────────

/// Streams all incomplete tasks assigned to a specific contractor.
///
/// Cross-scope: tasks come from any trade scope in any project.
/// Ordered by priority (urgent first) then due date.
/// StreamProvider.family parameterized by userId.
final myTasksProvider = StreamProvider.autoDispose
    .family<List<ProjectTask>, String>((ref, userId) {
  final dao = ref.watch(taskDaoProvider);
  return dao.watchTasksForContractor(userId);
});

// ────────────────────────────────────────────────────────────────────────────
// Task notes for a task — family provider parameterized by taskId
// ────────────────────────────────────────────────────────────────────────────

/// Streams all active notes for a given task, ordered newest-first.
///
/// StreamProvider.family — one instance per taskId. Auto-disposed
/// when the task detail screen is popped.
final taskNotesProvider = StreamProvider.autoDispose
    .family<List<TaskNote>, String>((ref, taskId) {
  final dao = ref.watch(taskNoteDaoProvider);
  return dao.watchByTask(taskId);
});

// ────────────────────────────────────────────────────────────────────────────
// Task attachments for a task — family providers parameterized by taskId
// ────────────────────────────────────────────────────────────────────────────

/// Streams all active attachments for a given task, ordered by sortOrder.
///
/// StreamProvider.family — one instance per taskId. Auto-disposed
/// when the task detail screen is popped.
final taskAttachmentsProvider = StreamProvider.autoDispose
    .family<List<TaskAttachment>, String>((ref, taskId) {
  final dao = ref.watch(taskAttachmentDaoProvider);
  return dao.watchByTask(taskId);
});

/// Streams the photo attachment count for a task.
///
/// Used for the photo gate check (task requires photoRequired=true photo).
final taskPhotoCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, taskId) {
  final dao = ref.watch(taskAttachmentDaoProvider);
  return dao.watchPhotoCountByTask(taskId);
});

/// Streams the document attachment count for a task.
///
/// Used for badge display and limit enforcement on document uploads.
final taskDocCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, taskId) {
  final dao = ref.watch(taskAttachmentDaoProvider);
  return dao.watchDocCountByTask(taskId);
});
