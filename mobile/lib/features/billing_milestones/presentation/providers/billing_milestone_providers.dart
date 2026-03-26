import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../data/billing_milestone_dao.dart';
import '../../domain/billing_milestone_entity.dart';

// ─── DAO provider ─────────────────────────────────────────────────────────────

/// Provider exposing the [BillingMilestoneDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [BillingMilestoneDao] is a database accessor
/// registered at startup in service_locator.dart. Riverpod providers that
/// need the DAO read it via this provider — dependency is explicit and
/// testable via ProviderScope overrides.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final billingMilestoneDaoProvider = Provider<BillingMilestoneDao>((ref) {
  return getIt<BillingMilestoneDao>();
});

// ─── Stream providers ─────────────────────────────────────────────────────────

/// Reactive stream of all non-deleted billing milestones for a trade scope.
///
/// Watches [BillingMilestoneDao.watchByScope] — offline-first, Drift-backed.
/// Ordered by sortOrder ascending (first milestone first).
/// Auto-disposed when no longer watched.
final billingMilestonesByScope =
    StreamProvider.autoDispose.family<List<BillingMilestoneEntity>, String>(
  (ref, scopeId) {
    final dao = ref.watch(billingMilestoneDaoProvider);
    return dao.watchByScope(scopeId);
  },
);

// ─── Action functions ─────────────────────────────────────────────────────────

/// Create a new billing milestone in the local Drift database.
///
/// Uses the [BillingMilestoneDao] transactional outbox dual-write pattern:
/// writes to billing_milestones table and enqueues a CREATE sync item.
/// Returns the generated milestone UUID.
Future<String> createMilestoneAction(
  WidgetRef ref,
  BillingMilestoneEntity entity,
) async {
  final dao = ref.read(billingMilestoneDaoProvider);
  return dao.createMilestone(entity);
}

/// Delete (soft-delete) a billing milestone by ID.
///
/// Writes a soft-delete timestamp and enqueues a DELETE sync item.
Future<void> deleteMilestoneAction(WidgetRef ref, String milestoneId) async {
  final dao = ref.read(billingMilestoneDaoProvider);
  return dao.deleteMilestone(milestoneId);
}
