import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/jobs/data/job_dao.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../domain/booking_entity.dart';
import '../../domain/overdue_service.dart';
import '../../domain/schedule_time_format.dart';
import '../providers/calendar_providers.dart';
import 'delay_justification_dialog.dart';

/// Date-grouped list of the contractor's bookings.
///
/// Groups by date with headers: "Today", "Tomorrow", "Wed, Mar 12" etc.
/// Shows bookings only for the selected date (uses watchBookingsByContractorAndDate
/// which is single-day scoped). For the multi-day list, a future enhancement
/// can extend to watchBookingsByContractorAndDate with a date range.
class ContractorBookingList extends StatelessWidget {
  const ContractorBookingList({
    required this.bookings,
    required this.jobMap,
    required this.contractorId,
    required this.selectedDate,
    super.key,
  });

  final List<BookingEntity> bookings;
  final Map<String, JobEntity> jobMap;
  final String contractorId;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No jobs scheduled',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              _dateSectionHeader(selectedDate),
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: bookings.length + 1, // +1 for section header
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              _dateSectionHeader(selectedDate),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 0.5,
              ),
            ),
          );
        }

        final booking = bookings[index - 1];
        final job = jobMap[booking.jobId];

        return _BookingListCard(
          booking: booking,
          job: job,
          contractorId: contractorId,
        );
      },
    );
  }

  String _dateSectionHeader(DateTime date) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final selectedDateNormalized =
        DateTime(date.year, date.month, date.day);

    final diffDays =
        selectedDateNormalized.difference(todayDate).inDays;

    if (diffDays == 0) return 'TODAY';
    if (diffDays == 1) return 'TOMORROW';
    if (diffDays == -1) return 'YESTERDAY';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[date.weekday - 1].toUpperCase()}, ${months[date.month - 1]} ${date.day}';
  }
}

/// Card for a single booking in the contractor list view.
///
/// Overdue jobs get amber/red background with prompt message.
/// "Report Delay" button shown for scheduled/in_progress status.
class _BookingListCard extends ConsumerWidget {
  const _BookingListCard({
    required this.booking,
    required this.job,
    required this.contractorId,
  });

  final BookingEntity booking;
  final JobEntity? job;
  final String contractorId;

  static const _activeStatuses = {'scheduled', 'in_progress'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider);
    final currentUserId = authState is AuthAuthenticated ? authState.userId : '';

    final status = job?.status ?? 'scheduled';
    final severity = job != null
        ? OverdueService.computeSeverity(job!.scheduledCompletionDate)
        : OverdueSeverity.none;

    final isOverdue = severity != OverdueSeverity.none;
    final canReportDelay = _activeStatuses.contains(status);

    Color cardColor = theme.colorScheme.surfaceContainerLow;
    if (severity == OverdueSeverity.critical) {
      cardColor = Colors.red.withValues(alpha: 0.08);
    } else if (severity == OverdueSeverity.warning) {
      cardColor = Colors.amber.withValues(alpha: 0.08);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isOverdue
              ? (severity == OverdueSeverity.critical
                  ? Colors.red.withValues(alpha: 0.5)
                  : Colors.amber.withValues(alpha: 0.5))
              : theme.dividerColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Job description + status chip
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    job?.description ?? 'Job',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: status),
              ],
            ),

            const SizedBox(height: 6),

            // Time range
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  ScheduleTimeFormat.range(
                      booking.timeRangeStart, booking.timeRangeEnd),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),

            // Overdue prompt
            if (isOverdue) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: severity == OverdueSeverity.critical
                        ? Colors.red
                        : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'This job is past its scheduled completion — '
                      'update status or report a delay',
                      style: TextStyle(
                        fontSize: 11,
                        color: severity == OverdueSeverity.critical
                            ? Colors.red[700]
                            : Colors.orange[800],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Report Delay button
            if (canReportDelay && job != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final jobDao = getIt<JobDao>();
                    final reported = await DelayJustificationDialog.show(
                      context: context,
                      jobDao: jobDao,
                      job: job!,
                      currentUserId: currentUserId,
                    );
                    if (reported && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Delay reported successfully'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.schedule_send, size: 14),
                  label: const Text('Report Delay',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(0, 30),
                    side: BorderSide(
                      color: isOverdue ? Colors.orange : Colors.grey[400]!,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColorMap[status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
