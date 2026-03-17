import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/jobs/presentation/providers/job_providers.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../../../features/users/presentation/providers/user_providers.dart';
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
///   - [clientName]: resolved from [companyUsersProvider] (not raw UUID)
///   - [contractorName]: resolved from [companyUsersProvider] (not raw UUID)
///
/// Items are sorted by severity (critical first) then by daysOverdue (most overdue first).
///
/// Watches [jobListNotifierProvider] — re-computes when Drift emits new data.
/// Returns empty list when [authNotifierProvider] is not [AuthAuthenticated].
final overdueJobsProvider = Provider<List<OverdueJobInfo>>((ref) {
  // Require authenticated state to resolve company-scoped user names.
  final authState = ref.watch(authNotifierProvider);
  if (authState is! AuthAuthenticated) {
    return [];
  }
  final companyId = authState.companyId;

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

  // Build a name lookup map from companyUsersProvider.
  // Falls back gracefully to empty map when users are not yet loaded.
  final usersAsync = ref.watch(companyUsersProvider(companyId));
  final userNames = usersAsync.maybeWhen(
    data: (users) => {for (final u in users) u.id: _displayName(u)},
    orElse: () => <String, String>{},
  );

  // Sort: critical first, then by daysOverdue descending.
  return jobs.map((job) => _toOverdueJobInfo(job, userNames)).toList()
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

/// Resolve a display name for a user.
///
/// Priority order:
///   1. "FirstName LastName" if both non-empty
///   2. firstName alone if only first available
///   3. Email username (before @) as fallback
String _displayName(UserEntity user) {
  final firstName = user.firstName ?? '';
  final lastName = user.lastName ?? '';
  if (firstName.isNotEmpty && lastName.isNotEmpty) {
    return '$firstName $lastName';
  }
  if (firstName.isNotEmpty) return firstName;
  return user.email.split('@').first;
}

/// Convert a [JobEntity] to [OverdueJobInfo], computing severity and delay data.
///
/// Uses [userNames] map (userId → displayName) to resolve client and contractor
/// names — falls back to the raw ID string if the user is not in the map.
OverdueJobInfo _toOverdueJobInfo(
  JobEntity job,
  Map<String, String> userNames,
) {
  final scheduledDate = job.scheduledCompletionDate;
  if (scheduledDate == null) {
    // Should not happen — isOverdue filters for non-null scheduledCompletionDate.
    // Defensive fallback: return a non-overdue entry.
    return OverdueJobInfo(
      jobId: job.id,
      description: job.description,
      scheduledCompletionDate: DateTime.now(),
      daysOverdue: 0,
      severity: OverdueSeverity.none,
      hasDelayReport: false,
    );
  }
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
    clientName: job.clientId != null
        ? userNames[job.clientId!] ?? job.clientId
        : null,
    contractorName: job.contractorId != null
        ? userNames[job.contractorId!] ?? job.contractorId
        : null,
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
