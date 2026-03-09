import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../domain/job_entity.dart';
import '../../domain/job_status.dart';
import '../providers/job_providers.dart';

/// Contractor's assigned job list — simple view for fieldwork.
///
/// Shows all active jobs assigned to the logged-in contractor.
/// Each card has big tap targets for quick status transitions.
///
/// Transitions allowed:
/// - Scheduled → In Progress (start working)
/// - In Progress → Complete (finish job)
///
/// Streams from local Drift DB via [contractorJobsNotifierProvider] —
/// offline-first; status transitions write to Drift + sync queue.
class ContractorJobsScreen extends ConsumerWidget {
  const ContractorJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(contractorJobsNotifierProvider);

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
              return ListView(
                // Wrap in ListView for pull-to-refresh to work when empty
                children: [
                  SizedBox(
                    height: 400,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.work_off_outlined,
                            size: 72,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            // Group jobs: Today / Upcoming / Completed
            final grouped = _groupJobs(jobs);
            final items = _buildItems(grouped);

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: items.length,
              itemBuilder: (context, index) => items[index],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  /// Group jobs into Today / Upcoming / Completed sections.
  _GroupedJobs _groupJobs(List<JobEntity> jobs) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final today = <JobEntity>[];
    final upcoming = <JobEntity>[];
    final completed = <JobEntity>[];

    for (final job in jobs) {
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
    return _GroupedJobs(today: today, upcoming: upcoming, completed: completed);
  }

  List<Widget> _buildItems(_GroupedJobs grouped) {
    final items = <Widget>[];

    void addSection(String title, List<JobEntity> sectionJobs) {
      if (sectionJobs.isEmpty) return;
      items.add(_SectionHeader(title: title, count: sectionJobs.length));
      for (final job in sectionJobs) {
        items.add(_ContractorJobCard(
          job: job,
          // onTap passed as placeholder; card handles navigation internally.
          onTap: () {},
        ));
      }
    }

    addSection('Today', grouped.today);
    addSection('Upcoming', grouped.upcoming);
    addSection('Completed', grouped.completed);
    return items;
  }
}

class _GroupedJobs {
  final List<JobEntity> today;
  final List<JobEntity> upcoming;
  final List<JobEntity> completed;
  const _GroupedJobs({
    required this.today,
    required this.upcoming,
    required this.completed,
  });
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
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Job card for contractor view — large action buttons for field use.
class _ContractorJobCard extends ConsumerWidget {
  final JobEntity job;
  final VoidCallback onTap;

  const _ContractorJobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _statusColor(job.jobStatus);
    final canStartWork = job.jobStatus == JobStatus.scheduled;
    final canComplete = job.jobStatus == JobStatus.inProgress;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        // Navigate to job detail on tap — ignore passed-in onTap placeholder.
        onTap: () => context.push(RouteNames.jobDetailPath(job.id)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status + priority row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      job.jobStatus.displayLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    job.priority.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                job.description,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                job.tradeType,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),

              // Action buttons — large tap targets for field use
              if (canStartWork || canComplete) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        _performTransition(context, ref, job),
                    icon: Icon(
                      canStartWork ? Icons.play_arrow : Icons.check_circle,
                    ),
                    label: Text(
                      canStartWork ? 'Start Work' : 'Mark Complete',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          canStartWork ? Colors.blue : Colors.green,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Perform the allowed forward transition for this job.
  ///
  /// Scheduled -> InProgress: "Start Work"
  /// InProgress -> Complete: "Mark Complete"
  ///
  /// Writes to Drift offline-first via [JobDao.updateJobStatus], which
  /// atomically enqueues a sync item. No network call needed here.
  Future<void> _performTransition(
      BuildContext context, WidgetRef ref, JobEntity j) async {
    final newStatus =
        j.jobStatus == JobStatus.scheduled ? 'in_progress' : 'complete';

    try {
      final authState = ref.read(authNotifierProvider);
      final userId =
          authState is AuthAuthenticated ? authState.userId : 'unknown';

      final dao = ref.read(jobDaoProvider);
      final now = DateTime.now();

      final history = List<Map<String, dynamic>>.from(j.statusHistory);
      history.add({
        'status': newStatus,
        'timestamp': now.toIso8601String(),
        'user_id': userId,
      });

      await dao.updateJobStatus(
        j.id,
        newStatus,
        jsonEncode(history),
        j.version + 1,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'in_progress' ? 'Job started' : 'Job completed',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _statusColor(JobStatus status) {
    return switch (status) {
      JobStatus.quote => Colors.grey,
      JobStatus.scheduled => Colors.blue,
      JobStatus.inProgress => Colors.orange,
      JobStatus.complete => Colors.green,
      JobStatus.invoiced => Colors.purple,
      JobStatus.cancelled => Colors.red,
    };
  }
}
