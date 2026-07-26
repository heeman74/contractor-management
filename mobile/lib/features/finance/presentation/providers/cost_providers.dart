import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to legacy in Riverpod 3 — explicitly imported.
// ignore: depend_on_referenced_packages
import 'package:riverpod/legacy.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../data/finance_repository.dart';

/// Effective permission keys for the current user, from GET /me/permissions
/// (the union across their roles, resolved server-side against the company
/// matrix — mirrors web's `usePermissions` hook). Not auto-disposed so the
/// gating check stays warm across screen navigation within a session.
final myPermissionsProvider = FutureProvider<Set<String>>((ref) async {
  final authState = ref.watch(authNotifierProvider);
  if (authState is! AuthAuthenticated) return const {};

  final dio = getIt<DioClient>();
  final response =
      await dio.instance.get<Map<String, dynamic>>('/me/permissions');
  final permissions = response.data?['permissions'];
  if (permissions is! List) {
    throw const FormatException(
      'Expected a List "permissions" field from /me/permissions',
    );
  }
  return permissions.whereType<String>().toSet();
});

/// The current user's finance.view / finance.manage state, derived from
/// [myPermissionsProvider]. `canView`/`canManage` are false while loading or
/// for a user without the key — gated UI stays hidden rather than flashing.
class FinancePermission {
  const FinancePermission({required this.canView, required this.canManage});

  final bool canView;
  final bool canManage;
}

final financePermissionProvider = Provider<FinancePermission>((ref) {
  final permissionsAsync = ref.watch(myPermissionsProvider);
  final permissions = permissionsAsync.maybeWhen(
    data: (perms) => perms,
    orElse: () => const <String>{},
  );
  return FinancePermission(
    canView: permissions.contains('finance.view'),
    canManage: permissions.contains('finance.manage'),
  );
});

// ────────────────────────────────────────────────────────────────────────────
// DAO / repository providers
// ────────────────────────────────────────────────────────────────────────────

/// Provider exposing the [CostEntryDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [CostEntryDao] is a database accessor
/// registered at startup in service_locator.dart. Riverpod providers that
/// need the DAO read it via this provider — dependency is explicit and
/// testable via ProviderScope overrides. (CLAUDE.md: document GetIt<->Riverpod
/// tradeoffs)
final costEntryDaoProvider = Provider<CostEntryDao>((ref) {
  return getIt<CostEntryDao>();
});

/// Provider exposing the [CostReceiptDao] singleton from GetIt.
///
/// NOTE: Same GetIt<->Riverpod tradeoff as [costEntryDaoProvider].
final costReceiptDaoProvider = Provider<CostReceiptDao>((ref) {
  return getIt<CostReceiptDao>();
});

/// Provider exposing the [FinanceRepository] singleton from GetIt.
///
/// NOTE: Same GetIt<->Riverpod tradeoff as [costEntryDaoProvider].
final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return getIt<FinanceRepository>();
});

// ────────────────────────────────────────────────────────────────────────────
// Cost categories — live lookup, not locally cached (31-04 decision)
// ────────────────────────────────────────────────────────────────────────────

/// The tenant's cost categories (materials/subcontractor/other/labor).
///
/// Fetched live from [FinanceRepository.fetchCostCategories] — no local
/// Drift table this plan (31-04 decision: categories are low-churn).
final costCategoriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repository = ref.watch(financeRepositoryProvider);
  return repository.fetchCostCategories();
});

/// A `categoryId -> name` lookup built from [costCategoriesProvider], for
/// display on [CostEntryCard] without each card re-deriving the map.
final costCategoryNameMapProvider = Provider<Map<String, String>>((ref) {
  final categoriesAsync = ref.watch(costCategoriesProvider);
  return categoriesAsync.maybeWhen(
    data: (categories) => {
      for (final category in categories)
        if (category['id'] is String && category['name'] is String)
          category['id'] as String: category['name'] as String,
    },
    orElse: () => const {},
  );
});

// ────────────────────────────────────────────────────────────────────────────
// Cost entries for a job — reactive Drift stream + background refresh
// ────────────────────────────────────────────────────────────────────────────

/// Reactive stream of active cost entries anchored to a job.
///
/// Reads from local Drift immediately (offline-first) and fires an on-demand
/// [FinanceRepository.fetchCostEntriesForJob] refresh in the background so
/// the list stays current with the server while showing cached data first.
final costEntriesForJobProvider =
    StreamProvider.autoDispose.family<List<CostEntry>, String>((ref, jobId) {
  final authState = ref.watch(authNotifierProvider);
  if (authState is AuthAuthenticated) {
    final companyId = authState.companyId;
    Future.microtask(() async {
      try {
        await ref
            .read(financeRepositoryProvider)
            .fetchCostEntriesForJob(companyId, jobId);
      } catch (e) {
        debugPrint('[cost_providers] fetchCostEntriesForJob failed: $e');
      }
    });
  }

  final dao = ref.watch(costEntryDaoProvider);
  return dao.watchByJob(jobId);
});

// ────────────────────────────────────────────────────────────────────────────
// Cost entries for a trade scope — reactive Drift stream + background refresh
// ────────────────────────────────────────────────────────────────────────────

/// Reactive stream of active cost entries anchored to a trade scope.
///
/// Same cache-first-then-refresh pattern as [costEntriesForJobProvider].
final costEntriesForTradeScopeProvider = StreamProvider.autoDispose
    .family<List<CostEntry>, String>((ref, tradeScopeId) {
  final authState = ref.watch(authNotifierProvider);
  if (authState is AuthAuthenticated) {
    final companyId = authState.companyId;
    Future.microtask(() async {
      try {
        await ref
            .read(financeRepositoryProvider)
            .fetchCostEntriesForTradeScope(companyId, tradeScopeId);
      } catch (e) {
        debugPrint(
            '[cost_providers] fetchCostEntriesForTradeScope failed: $e');
      }
    });
  }

  final dao = ref.watch(costEntryDaoProvider);
  return dao.watchByTradeScope(tradeScopeId);
});

// ────────────────────────────────────────────────────────────────────────────
// Project cost rollup — on-demand fetch drives the local watch's jobIds
// ────────────────────────────────────────────────────────────────────────────

/// Job IDs known to anchor at least one cost entry in a project's rollup.
///
/// Populated by [costRollupTotalProvider] after its fetch — the mobile
/// `Jobs` table carries no `projectId` FK (31-04 decision), so this is the
/// only source of job-anchored membership for [CostEntryDao.watchByProject]
/// on mobile. Starts empty: on cold load, only trade-scope-anchored entries
/// (which ARE derivable locally) show until the first fetch completes.
final _projectJobIdsProvider = StateProvider.autoDispose
    .family<List<String>, String>((ref, projectId) => const []);

/// Reactive stream of the itemized cost entries backing a project's rollup.
///
/// Watches local Drift via [CostEntryDao.watchByProject], keyed on the
/// job IDs discovered by the most recent [costRollupTotalProvider] fetch.
final costRollupForProjectProvider = StreamProvider.autoDispose
    .family<List<CostEntry>, String>((ref, projectId) {
  final authState = ref.watch(authNotifierProvider);
  if (authState is! AuthAuthenticated) {
    return Stream.value(const <CostEntry>[]);
  }

  final jobIds = ref.watch(_projectJobIdsProvider(projectId));
  final dao = ref.watch(costEntryDaoProvider);
  return dao.watchByProject(authState.companyId, projectId, jobIds: jobIds);
});

/// The authoritative backend-computed total for a project's cost rollup
/// (Pitfall 5 — never locally-summed).
///
/// Triggers [FinanceRepository.fetchProjectRollup], which upserts entries
/// into Drift and reports the job IDs found — written to
/// [_projectJobIdsProvider] so [costRollupForProjectProvider] picks up
/// job-anchored entries on the next rebuild.
final costRollupTotalProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, projectId) async {
  final authState = ref.read(authNotifierProvider);
  if (authState is! AuthAuthenticated) return null;

  final repository = ref.read(financeRepositoryProvider);
  final result =
      await repository.fetchProjectRollup(authState.companyId, projectId);
  ref.read(_projectJobIdsProvider(projectId).notifier).state = result.jobIds;
  return result.total;
});

// ────────────────────────────────────────────────────────────────────────────
// Receipts for a cost entry — reactive Drift stream + background refresh
// ────────────────────────────────────────────────────────────────────────────

/// Reactive stream of active receipts for a cost entry.
///
/// Same cache-first-then-refresh pattern as [costEntriesForJobProvider].
final receiptsForCostEntryProvider = StreamProvider.autoDispose
    .family<List<CostReceipt>, String>((ref, costEntryId) {
  final authState = ref.watch(authNotifierProvider);
  if (authState is AuthAuthenticated) {
    final companyId = authState.companyId;
    Future.microtask(() async {
      try {
        await ref
            .read(financeRepositoryProvider)
            .fetchReceipts(companyId, costEntryId);
      } catch (e) {
        debugPrint('[cost_providers] fetchReceipts failed: $e');
      }
    });
  }

  final dao = ref.watch(costReceiptDaoProvider);
  return dao.watchByCostEntry(costEntryId);
});
