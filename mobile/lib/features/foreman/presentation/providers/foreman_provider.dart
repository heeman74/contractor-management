import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../data/foreman_repository.dart';

/// Provider exposing the [ForemanRepository] singleton from GetIt.
///
/// NOTE: GetIt is used here because [ForemanRepository] is registered at
/// startup in service_locator.dart. Riverpod providers that need the
/// repository read it via this provider — dependency is explicit and
/// testable via ProviderScope overrides.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final foremanRepositoryProvider = Provider<ForemanRepository>((ref) {
  return getIt<ForemanRepository>();
});

/// Fetches the list of projects assigned to the current foreman.
///
/// FutureProvider — auto-disposed when no longer watched.
/// Returns List<Map<String, dynamic>> from the API.
final assignedProjectsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(foremanRepositoryProvider);
  return repo.fetchAssignedProjects();
});

/// Fetches the status update history for a given project.
///
/// FutureProvider.family — one instance per projectId.
/// Returns List<Map<String, dynamic>> from the API.
final statusUpdatesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, projectId) async {
  final repo = ref.watch(foremanRepositoryProvider);
  return repo.fetchStatusUpdates(projectId);
});

/// Fetches the most recent status update for a given project.
///
/// FutureProvider.family — one instance per projectId.
/// Returns null if no updates exist.
final latestStatusProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, projectId) async {
  final repo = ref.watch(foremanRepositoryProvider);
  return repo.fetchLatestStatus(projectId);
});
