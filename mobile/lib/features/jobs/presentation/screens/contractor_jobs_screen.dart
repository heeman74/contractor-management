import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../domain/job_entity.dart';
import '../../domain/job_status.dart';
import '../providers/job_providers.dart';
import '../providers/timer_providers.dart';
import '../widgets/contractor_job_card.dart';

/// Contractor's assigned job list — field dashboard view.
///
/// Shows all active jobs assigned to the logged-in contractor.
/// Redesigned in Plan 06-05 with:
/// - Active (clocked-in) job pinned to top with highlighted border + elapsed timer.
/// - Completed jobs dimmed (opacity 0.6) with total tracked time, no action bar.
/// - Job cards have action bar: [Add Note] [Camera] [Clock In/Out].
/// - Status transitions via long-press on the status badge.
///
/// Sorting: active job first → Today → Upcoming → Completed.
///
/// Streams from local Drift DB via [contractorJobsNotifierProvider] —
/// offline-first; status transitions write to Drift + sync queue.
class ContractorJobsScreen extends ConsumerWidget {
  const ContractorJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(contractorJobsNotifierProvider);
    final timerAsync = ref.watch(timerNotifierProvider);
    final activeJobId = timerAsync.value?.activeJobId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Jobs'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await getIt<SyncEngine>().syncNow();
        },
        child: jobsAsync.when(
          data: (jobs) {
            if (jobs.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  return ListView(
                    // Wrap in ListView for pull-to-refresh to work when empty
                    children: [
                      SizedBox(
                        height: constraints.maxHeight,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.work_off_outlined,
                                size: 72,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'No jobs assigned to you',
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Jobs assigned by your admin will appear here.\nPull down to sync.',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }

            final items = _buildItems(context, jobs, activeJobId);
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: items.length,
              itemBuilder: (context, index) => items[index],
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  List<Widget> _buildItems(
    BuildContext context,
    List<JobEntity> jobs,
    String? activeJobId,
  ) {
    final items = <Widget>[];

    // Separate into groups: active, today, upcoming, completed.
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    JobEntity? activeJob;
    final today = <JobEntity>[];
    final upcoming = <JobEntity>[];
    final completed = <JobEntity>[];

    for (final job in jobs) {
      // Pin the active (clocked-in) job to the top regardless of status.
      if (activeJobId != null && job.id == activeJobId) {
        activeJob = job;
        continue;
      }

      if (job.jobStatus == JobStatus.complete ||
          job.jobStatus == JobStatus.invoiced ||
          job.jobStatus == JobStatus.cancelled) {
        completed.add(job);
        continue;
      }

      final reference = job.scheduledCompletionDate ?? job.createdAt;
      if (reference.isAfter(todayStart) && reference.isBefore(todayEnd)) {
        today.add(job);
      } else {
        upcoming.add(job);
      }
    }

    void addSection(String title, List<JobEntity> sectionJobs) {
      if (sectionJobs.isEmpty) return;
      items.add(_SectionHeader(title: title, count: sectionJobs.length));
      for (final job in sectionJobs) {
        items.add(ContractorJobCard(job: job));
      }
    }

    // Active job at top with its own header.
    if (activeJob != null) {
      items.add(_SectionHeader(title: 'Active', count: 1));
      items.add(ContractorJobCard(job: activeJob));
    }

    addSection('Today', today);
    addSection('Upcoming', upcoming);
    addSection('Completed', completed);

    return items;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
