import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/jobs/presentation/providers/job_providers.dart';
import '../../domain/overdue_service.dart';

// ────────────────────────────────────────────────────────────────────────────
// OverdueJobInfo data model
// ────────────────────────────────────────────────────────────────────────────

/// Rich overdue job metadata used by [OverduePanel] for display.
///
/// Derived from [JobEntity] + [OverdueService] computation.
/// Includes tiered severity, days overdue count, and the latest delay reason
/// if a delay was reported via the delay justification flow.
class OverdueJobInfo {
  const OverdueJobInfo({
    required this.jobId,
    required this.description,
    required this.scheduledCompletionDate,
    required this.daysOverdue,
    required this.severity,
    required this.hasDelayReport,
    this.clientName,
    this.contractorName,
    this.latestDelayReason,
  });

  /// Unique job identifier.
  final String jobId;

  /// Human-readable job description.
  final String description;

  /// Client name derived from client profile data (null if not loaded).
  final String? clientName;

  /// Contractor name derived from user data (null if unassigned).
  final String? contractorName;

  /// Date the job was originally scheduled to be completed.
  final DateTime scheduledCompletionDate;

  /// Calendar days since scheduled completion date.
  final int daysOverdue;

  /// Severity tier for color-coded UI indicators.
  final OverdueSeverity severity;

  /// True if the most recent status_history entry has type "delay".
  ///
  /// When true, [latestDelayReason] is populated from that entry.
  final bool hasDelayReport;

  /// The reason text from the most recent delay report, or null if none.
  final String? latestDelayReason;
}

// ────────────────────────────────────────────────────────────────────────────
// Overdue job providers
// ────────────────────────────────────────────────────────────────────────────

/// Derived provider returning all overdue jobs as enriched [OverdueJobInfo].
///
/// Filters the company's local job list using [OverdueService.isOverdue]:
///   - status must be 'scheduled' or 'in_progress'
///   - today must be past [scheduledCompletionDate]
///
/// Enhances each overdue job with:
///   - [daysOverdue]: calendar days past the scheduled completion date
///   - [severity]: [OverdueSeverity] tier (warning or critical)
///   - [hasDelayReport]: true if last status_history entry type == "delay"
///   - [latestDelayReason]: reason text from the last delay entry
///
/// Items are sorted by severity (critical first) then by daysOverdue (most overdue first).
///
/// Watches [jobListNotifierProvider] — re-computes when Drift emits new data.
final overdueJobsProvider = Provider<List<OverdueJobInfo>>((ref) {
  final jobsAsync = ref.watch(jobListNotifierProvider);
  final jobs = jobsAsync.maybeWhen(
    data: (jobs) => jobs
        .where(
          (job) =>
              OverdueService.isOverdue(job.status, job.scheduledCompletionDate),
        )
        .toList(),
    orElse: () => <JobEntity>[],
  );

  // Sort: critical first, then by daysOverdue descending.
  return jobs.map(_toOverdueJobInfo).toList()
    ..sort((a, b) {
      final severityCompare =
          _severityOrder(b.severity) - _severityOrder(a.severity);
      if (severityCompare != 0) return severityCompare;
      return b.daysOverdue.compareTo(a.daysOverdue);
    });
});

/// Derived provider returning the count of overdue jobs.
///
/// Used by [AppShell] bottom nav badge and schedule screen header.
/// Derived from [overdueJobsProvider] so both stay in sync.
final overdueJobCountProvider = Provider<int>((ref) {
  return ref.watch(overdueJobsProvider).length;
});

// ────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ────────────────────────────────────────────────────────────────────────────

/// Convert a [JobEntity] to [OverdueJobInfo], computing severity and delay data.
OverdueJobInfo _toOverdueJobInfo(JobEntity job) {
  final scheduledDate = job.scheduledCompletionDate!;
  final severity = OverdueService.computeSeverity(scheduledDate);

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final dueDate = DateTime(
    scheduledDate.year,
    scheduledDate.month,
    scheduledDate.day,
  );
  final daysOverdue = todayStart.difference(dueDate).inDays.clamp(0, 9999);

  // Inspect the most recent status_history entry for a delay report.
  bool hasDelayReport = false;
  String? latestDelayReason;
  if (job.statusHistory.isNotEmpty) {
    final lastEntry = job.statusHistory.last;
    final entryType = lastEntry['type'] as String?;
    if (entryType == 'delay') {
      hasDelayReport = true;
      latestDelayReason = lastEntry['reason'] as String?;
    }
  }

  return OverdueJobInfo(
    jobId: job.id,
    description: job.description,
    clientName: job.clientId, // TODO: resolve from ClientProfile in future plan
    contractorName: job.contractorId, // TODO: resolve from User in future plan
    scheduledCompletionDate: scheduledDate,
    daysOverdue: daysOverdue,
    severity: severity,
    hasDelayReport: hasDelayReport,
    latestDelayReason: latestDelayReason,
  );
}

/// Numeric sort weight for [OverdueSeverity] — higher = more severe.
int _severityOrder(OverdueSeverity severity) {
  return switch (severity) {
    OverdueSeverity.critical => 2,
    OverdueSeverity.warning => 1,
    OverdueSeverity.none => 0,
  };
}
