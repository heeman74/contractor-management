import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/jobs/presentation/providers/job_providers.dart';
import '../../domain/overdue_service.dart';

// ────────────────────────────────────────────────────────────────────────────
// Overdue job providers
// ────────────────────────────────────────────────────────────────────────────

/// Derived provider returning all jobs currently considered overdue.
///
/// Filters the company's local job list using [OverdueService.isOverdue]:
///   - status must be 'scheduled' or 'in_progress'
///   - today must be past [scheduledCompletionDate]
///
/// Watches [jobListNotifierProvider] — re-computes when Drift emits new data.
/// The result drives the overdue count badge in the ScheduleScreen header.
final overdueJobsProvider = Provider<List<JobEntity>>((ref) {
  final jobsAsync = ref.watch(jobListNotifierProvider);
  return jobsAsync.maybeWhen(
    data: (jobs) => jobs
        .where(
          (job) =>
              OverdueService.isOverdue(job.status, job.scheduledCompletionDate),
        )
        .toList(),
    orElse: () => [],
  );
});

/// Derived provider returning the count of overdue jobs.
///
/// Used by the schedule screen header to show the red badge count.
/// Derived from [overdueJobsProvider] so both stay in sync with the same
/// underlying computation.
final overdueJobCountProvider = Provider<int>((ref) {
  return ref.watch(overdueJobsProvider).length;
});
