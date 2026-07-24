import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import '../../domain/schedule_time_format.dart';
import 'unscheduled_jobs_drawer.dart';

/// Filterable job list bottom sheet for tap-to-schedule.
///
/// Shows jobs without bookings for the current date. Admin selects a job
/// to schedule it at the tapped time slot.
class TapToScheduleSheet extends ConsumerStatefulWidget {
  const TapToScheduleSheet({
    required this.slotStart,
    required this.contractor,
    required this.companyId,
    required this.jobs,
    required this.existingBookings,
    required this.onJobSelected,
    super.key,
  });

  final DateTime slotStart;
  final UserEntity contractor;
  final String companyId;
  final Map<String, JobEntity> jobs;
  final List<BookingEntity> existingBookings;
  final Future<void> Function(JobEntity job) onJobSelected;

  @override
  ConsumerState<TapToScheduleSheet> createState() => _TapToScheduleSheetState();
}

class _TapToScheduleSheetState extends ConsumerState<TapToScheduleSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unscheduledJobsAsync = ref.watch(unscheduledJobsProvider);
    final searchText = _searchController.text.toLowerCase();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Schedule at ${ScheduleTimeFormat.time(widget.slotStart)}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),

            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search jobs...',
                  prefixIcon: Icon(Icons.search, size: 16),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),

            const Divider(height: 1),

            // Job list
            Expanded(
              child: unscheduledJobsAsync.when(
                data: (unscheduledJobs) {
                  // Filter by search text
                  final filtered = unscheduledJobs.where((j) {
                    if (searchText.isEmpty) return true;
                    return j.description.toLowerCase().contains(searchText) ||
                        (j.clientId?.toLowerCase().contains(searchText) ??
                            false);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 36, color: Colors.green),
                          const SizedBox(height: 8),
                          Text(
                            'All jobs scheduled',
                            style:
                                TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final driftJob = filtered[index];
                      // Try to find matching JobEntity for full details
                      final jobEntity = widget.jobs[driftJob.id];

                      return ListTile(
                        dense: true,
                        title: Text(
                          driftJob.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${driftJob.tradeType}'
                          '${driftJob.estimatedDurationMinutes != null ? '  •  ${ScheduleTimeFormat.duration(driftJob.estimatedDurationMinutes!)}' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            driftJob.status,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onTap: () {
                          if (jobEntity != null) {
                            widget.onJobSelected(jobEntity);
                          }
                        },
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Error loading jobs',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
