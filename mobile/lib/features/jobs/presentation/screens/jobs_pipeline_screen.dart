import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../domain/job_entity.dart';
import '../../domain/job_status.dart';
import '../providers/job_providers.dart';
import '../widgets/job_card.dart';
import '../widgets/kanban_board.dart';

/// Admin job pipeline screen — primary job management hub for dispatchers.
///
/// Replaces the Phase 1 [JobsScreen] placeholder. Features:
///   - Toggle between kanban board and filtered list view
///   - FAB / AppBar "+" to launch the 4-step job wizard
///   - Filter chips (status, trade type, priority, contractor, client)
///   - Batch operations: long-press activates multi-select; bulk-transitions
///   - Pull-to-refresh triggers [SyncEngine.syncNow]
///   - Empty state with "Create your first job" prompt
///
/// All data streams from local Drift DB via [jobListNotifierProvider] —
/// updates appear immediately when the DB changes (offline-first).
class JobsPipelineScreen extends ConsumerWidget {
  const JobsPipelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(jobListNotifierProvider);
    final isKanban = ref.watch(isKanbanViewProvider);
    final isBatchMode = ref.watch(isBatchModeProvider);
    final selectedIds = ref.watch(selectedJobIdsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await getIt<SyncEngine>().syncNow();
      },
      child: Stack(
        children: [
          Column(
            children: [
              // Toolbar: view toggle + filter row
              _PipelineToolbar(isKanban: isKanban, isBatchMode: isBatchMode),

              // Main content
              Expanded(
                child: jobsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (jobs) {
                    if (jobs.isEmpty) {
                      return const _EmptyJobsState();
                    }
                    if (isKanban) {
                      return KanbanBoard(
                        jobs: jobs,
                        onJobTap: (id) =>
                            context.push(RouteNames.jobDetailPath(id)),
                      );
                    }
                    return _JobListView(
                      jobs: _applyFilters(jobs, ref),
                    );
                  },
                ),
              ),
            ],
          ),

          // Batch mode action bar — bulk status transition
          if (isBatchMode && selectedIds.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _BatchActionBar(
                selectedCount: selectedIds.length,
                onClearSelection: () {
                  ref.read(selectedJobIdsProvider.notifier).state = {};
                  ref.read(isBatchModeProvider.notifier).state = false;
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Apply all active filter providers to the job list.
  List<JobEntity> _applyFilters(List<JobEntity> jobs, WidgetRef ref) {
    final statusFilter = ref.watch(statusFilterProvider);
    final tradeFilter = ref.watch(tradeTypeFilterProvider);
    final priorityFilter = ref.watch(priorityFilterProvider);
    final contractorFilter = ref.watch(contractorFilterProvider);
    final clientFilter = ref.watch(clientFilterProvider);

    return jobs.where((j) {
      if (statusFilter != null && j.status != statusFilter) return false;
      if (tradeFilter != null && j.tradeType != tradeFilter) return false;
      if (priorityFilter != null && j.priority != priorityFilter) return false;
      if (contractorFilter != null &&
          j.contractorId != contractorFilter) return false;
      if (clientFilter != null && j.clientId != clientFilter) return false;
      return true;
    }).toList();
  }
}

// ─── Toolbar ─────────────────────────────────────────────────────────────────

class _PipelineToolbar extends ConsumerWidget {
  const _PipelineToolbar({
    required this.isKanban,
    required this.isBatchMode,
  });

  final bool isKanban;
  final bool isBatchMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      elevation: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top action row: view toggle + new job button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                // View toggle (SegmentedButton — Material 3)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.view_module_outlined),
                      label: Text('Kanban'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.view_list_outlined),
                      label: Text('List'),
                    ),
                  ],
                  selected: {isKanban},
                  onSelectionChanged: (selection) {
                    ref.read(isKanbanViewProvider.notifier).state =
                        selection.first;
                    // Exit batch mode when switching views
                    if (isBatchMode) {
                      ref.read(isBatchModeProvider.notifier).state = false;
                      ref.read(selectedJobIdsProvider.notifier).state = {};
                    }
                  },
                  showSelectedIcon: false,
                ),
                const Spacer(),
                // New job button
                FilledButton.icon(
                  onPressed: () => context.push('/jobs/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('New Job'),
                ),
              ],
            ),
          ),

          // Filter chips row (list view only)
          if (!isKanban) const _FilterChipsRow(),
        ],
      ),
    );
  }
}

// ─── Filter chips ─────────────────────────────────────────────────────────────

class _FilterChipsRow extends ConsumerWidget {
  const _FilterChipsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusFilter = ref.watch(statusFilterProvider);

    // All statuses shown as filter chips in list view (including Cancelled)
    const statuses = [
      null, // "All"
      'quote',
      'scheduled',
      'in_progress',
      'complete',
      'invoiced',
      'cancelled',
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: statuses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final status = statuses[index];
          final label = status == null
              ? 'All'
              : JobStatus.fromString(status).displayLabel;
          return FilterChip(
            label: Text(label),
            selected: statusFilter == status,
            onSelected: (_) {
              ref.read(statusFilterProvider.notifier).state = status;
            },
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

// ─── List view ────────────────────────────────────────────────────────────────

class _JobListView extends ConsumerWidget {
  const _JobListView({required this.jobs});

  final List<JobEntity> jobs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBatchMode = ref.watch(isBatchModeProvider);
    final selectedIds = ref.watch(selectedJobIdsProvider);

    if (jobs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No jobs match the current filters.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: jobs.length,
      itemBuilder: (context, index) {
        final job = jobs[index];
        return JobCard(
          job: job,
          isSelected: selectedIds.contains(job.id),
          inBatchMode: isBatchMode,
          onTap: () => context.push(RouteNames.jobDetailPath(job.id)),
          onLongPress: () {
            // Activate batch mode on long-press
            ref.read(isBatchModeProvider.notifier).state = true;
            ref.read(selectedJobIdsProvider.notifier).state = {job.id};
          },
          onSelectionChanged: (selected) {
            final current = Set<String>.from(selectedIds);
            if (selected) {
              current.add(job.id);
            } else {
              current.remove(job.id);
            }
            ref.read(selectedJobIdsProvider.notifier).state = current;
          },
        );
      },
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyJobsState extends StatelessWidget {
  const _EmptyJobsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.work_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            const Text(
              'No jobs yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first job to get started.',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/jobs/new'),
              icon: const Icon(Icons.add),
              label: const Text('Create your first job'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Batch action bar ─────────────────────────────────────────────────────────

class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({
    required this.selectedCount,
    required this.onClearSelection,
  });

  final int selectedCount;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              '$selectedCount selected',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: onClearSelection,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                // Bulk status transition — forward-only for selected jobs.
                // Full implementation: show status picker dialog, then call
                // jobDao.updateJobStatus for each selected job.
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Bulk transition for $selectedCount jobs — pick status',
                    ),
                  ),
                );
              },
              child: const Text('Transition Status'),
            ),
          ],
        ),
      ),
    );
  }
}
