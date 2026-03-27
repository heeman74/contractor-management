import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../providers/foreman_provider.dart';

/// Screen displaying the list of past status updates for a project.
///
/// Shows a scrollable list of status update cards, each displaying:
/// date, status text, weather, worker count, safety incidents, and blockers.
/// Supports pull-to-refresh to reload from the API.
class StatusHistoryScreen extends ConsumerWidget {
  const StatusHistoryScreen({
    required this.projectId, super.key,
    this.projectName,
  });

  final String projectId;
  final String? projectName;

  static const _tag = 'StatusHistoryScreen';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusUpdates = ref.watch(statusUpdatesProvider(projectId));

    return Scaffold(
      appBar: AppBar(
        title: Text(projectName ?? 'Status History'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(statusUpdatesProvider(projectId));
        },
        child: statusUpdates.when(
          data: (updates) {
            if (updates.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 100),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.article_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No status updates yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Pull down to refresh',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: updates.length,
              itemBuilder: (context, index) {
                final update = updates[index];
                return _StatusUpdateCard(update: update);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, st) {
            AppLogger.error(
              _tag,
              'Failed to load status updates',
              error: error,
              stackTrace: st,
            );
            return ListView(
              children: [
                const SizedBox(height: 100),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to load status updates',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pull down to retry',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusUpdateCard extends StatelessWidget {
  const _StatusUpdateCard({required this.update});

  final Map<String, dynamic> update;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Safe field extraction using `is` checks — never bare `as` casts.
    final reportDate = update['report_date'] is String
        ? update['report_date'] as String
        : 'Unknown date';
    final statusText = update['status_text'] is String
        ? update['status_text'] as String
        : '';
    final weather = update['weather_conditions'] is String
        ? update['weather_conditions'] as String
        : null;
    final workers = update['workers_on_site'] is int
        ? update['workers_on_site'] as int
        : null;
    final safetyIncidents = update['safety_incidents'] is int
        ? update['safety_incidents'] as int
        : 0;
    final blockers = update['blockers'] is String
        ? update['blockers'] as String
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  reportDate,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (safetyIncidents > 0)
                  Chip(
                    avatar: const Icon(Icons.warning_amber,
                        size: 16, color: Colors.white),
                    label: Text('$safetyIncidents incident(s)'),
                    backgroundColor: theme.colorScheme.error,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Status text
            Text(
              statusText,
              style: theme.textTheme.bodyMedium,
            ),

            // Metadata chips row
            if (weather != null || workers != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (weather != null)
                    Chip(
                      avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
                      label: Text(weather),
                      labelStyle: const TextStyle(fontSize: 12),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (workers != null)
                    Chip(
                      avatar: const Icon(Icons.people_outlined, size: 16),
                      label: Text('$workers workers'),
                      labelStyle: const TextStyle(fontSize: 12),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],

            // Blockers section
            if (blockers != null && blockers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.block_outlined,
                            size: 16,
                            color: theme.colorScheme.error),
                        const SizedBox(width: 4),
                        Text(
                          'Blockers',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      blockers,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
