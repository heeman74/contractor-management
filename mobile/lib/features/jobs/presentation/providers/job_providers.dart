import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../data/job_dao.dart';
import '../../domain/job_entity.dart';

/// Provider exposing the [JobDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [JobDao] is a database accessor registered
/// at startup in service_locator.dart. Riverpod providers that need the DAO
/// read it via this provider — dependency is explicit and testable via
/// ProviderScope overrides. (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final jobDaoProvider = Provider<JobDao>((ref) {
  return getIt<JobDao>();
});

// ────────────────────────────────────────────────────────────────────────────
// Pipeline view toggle
// ────────────────────────────────────────────────────────────────────────────

/// Whether the job pipeline is displayed as a kanban board (true) or list (false).
///
/// Toggled by the AppBar action button in [JobsPipelineScreen].
final isKanbanViewProvider = StateProvider<bool>((ref) => true);

// ────────────────────────────────────────────────────────────────────────────
// Pipeline filter state
// ────────────────────────────────────────────────────────────────────────────

/// Currently selected status filter for the list view (null = all statuses).
final statusFilterProvider = StateProvider<String?>((ref) => null);

/// Currently selected trade-type filter (null = all trade types).
final tradeTypeFilterProvider = StateProvider<String?>((ref) => null);

/// Currently selected priority filter (null = all priorities).
final priorityFilterProvider = StateProvider<String?>((ref) => null);

/// Currently selected contractor ID filter (null = all contractors).
final contractorFilterProvider = StateProvider<String?>((ref) => null);

/// Currently selected client ID filter (null = all clients).
final clientFilterProvider = StateProvider<String?>((ref) => null);

// ────────────────────────────────────────────────────────────────────────────
// Admin — all jobs for company
// ────────────────────────────────────────────────────────────────────────────

/// Streams ALL active jobs for the current company from Drift.
///
/// Uses [AsyncNotifier] because [build()] must await the auth state before
/// setting up the stream subscription. The stream stays live for the lifetime
/// of the provider, re-emitting on every Drift DB change (offline-first).
class JobListNotifier extends AsyncNotifier<List<JobEntity>> {
  @override
  Future<List<JobEntity>> build() async {
    final authState = ref.watch(authNotifierProvider);

    if (authState is! AuthAuthenticated) {
      return [];
    }

    final dao = ref.watch(jobDaoProvider);
    final companyId = authState.companyId;

    // switchMap: cancel previous stream subscription when companyId changes.
    final stream = dao.watchJobsByCompany(companyId);

    // Keep the provider alive while the stream emits; propagate errors.
    final sub = stream.listen(
      (jobs) => state = AsyncData(jobs),
      onError: (Object e, StackTrace st) => state = AsyncError(e, st),
    );
    ref.onDispose(sub.cancel);

    // Return the first snapshot synchronously so the UI can paint immediately.
    return await stream.first;
  }
}

/// Provider for [JobListNotifier].
final jobListNotifierProvider =
    AsyncNotifierProvider<JobListNotifier, List<JobEntity>>(
  JobListNotifier.new,
);

// ────────────────────────────────────────────────────────────────────────────
// Contractor — own assigned jobs
// ────────────────────────────────────────────────────────────────────────────

/// Streams all active jobs assigned to the currently logged-in contractor.
///
/// Used in [ContractorJobsScreen].
class ContractorJobsNotifier extends AsyncNotifier<List<JobEntity>> {
  @override
  Future<List<JobEntity>> build() async {
    final authState = ref.watch(authNotifierProvider);

    if (authState is! AuthAuthenticated) {
      return [];
    }

    final dao = ref.watch(jobDaoProvider);
    final userId = authState.userId;

    final stream = dao.watchJobsByContractor(userId);

    final sub = stream.listen(
      (jobs) => state = AsyncData(jobs),
      onError: (Object e, StackTrace st) => state = AsyncError(e, st),
    );
    ref.onDispose(sub.cancel);

    return await stream.first;
  }
}

/// Provider for [ContractorJobsNotifier].
final contractorJobsNotifierProvider =
    AsyncNotifierProvider<ContractorJobsNotifier, List<JobEntity>>(
  ContractorJobsNotifier.new,
);

// ────────────────────────────────────────────────────────────────────────────
// Single job detail — family provider parameterized by jobId
// ────────────────────────────────────────────────────────────────────────────

/// Streams a single [JobEntity] by ID from Drift.
///
/// Family provider — one instance per jobId. Automatically disposed when the
/// job detail screen is popped off the navigation stack.
class JobDetailNotifier extends FamilyAsyncNotifier<JobEntity?, String> {
  @override
  Future<JobEntity?> build(String arg) async {
    final dao = ref.watch(jobDaoProvider);
    final jobId = arg;

    // Watch the company's jobs and filter to the specific ID.
    // When upstream changes, this provider re-emits automatically.
    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthAuthenticated) return null;

    final stream = dao
        .watchJobsByCompany(authState.companyId)
        .map((jobs) => jobs.where((j) => j.id == jobId).firstOrNull);

    final sub = stream.listen(
      (job) => state = AsyncData(job),
      onError: (Object e, StackTrace st) => state = AsyncError(e, st),
    );
    ref.onDispose(sub.cancel);

    return await stream.first;
  }
}

/// Provider for [JobDetailNotifier] — parameterized by jobId.
final jobDetailNotifierProvider =
    AsyncNotifierProvider.family<JobDetailNotifier, JobEntity?, String>(
  JobDetailNotifier.new,
);

// ────────────────────────────────────────────────────────────────────────────
// Multi-select state for batch operations in pipeline list view
// ────────────────────────────────────────────────────────────────────────────

/// Set of selected job IDs in multi-select mode (empty = single-select mode).
final selectedJobIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Whether batch mode is active (long-press activates it).
final isBatchModeProvider = StateProvider<bool>((ref) => false);
