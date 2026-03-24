import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart' show Project;
import '../../../../core/routing/route_names.dart';
import '../providers/project_providers.dart';
import '../widgets/project_status_badge.dart';
import '../widgets/trade_progress_card.dart';

/// Project detail screen — shows project info and trade scope cards.
///
/// Displays:
/// - AppBar with project name and status badge
/// - ListView of [TradeScopeCard] widgets (one per active scope)
/// - "Add Trade Scope" stub button at bottom
/// - Empty state when no scopes exist
class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get project info from the list provider (avoids a separate getById provider)
    final projectsAsync = ref.watch(projectListProvider);
    final scopesAsync = ref.watch(tradeScopesProvider(projectId));

    // Extract project from cached async state without triggering loading indicator
    Project? project;
    if (projectsAsync is AsyncData<List<Project>>) {
      project = projectsAsync.value
          .where((p) => p.id == projectId)
          .firstOrNull;
    }

    final projectName = project?.name ?? 'Project';
    final projectStatus = project?.status ?? 'draft';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                projectName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ProjectStatusBadge(status: projectStatus),
          ],
        ),
        actions: [
          // Timeline (Gantt chart) button — Phase 20 dependency engine
          IconButton(
            icon: const Icon(Icons.timeline),
            tooltip: 'View Timeline',
            onPressed: () => context.push(
              RouteNames.projectGanttPath(projectId),
              extra: projectName,
            ),
          ),
        ],
      ),
      body: scopesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading trade scopes: $error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        ),
        data: (scopes) {
          if (scopes.isEmpty) {
            return _EmptyScopesState(
              onAddScope: () => _showAddScopeStub(context),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  itemCount: scopes.length,
                  itemBuilder: (context, index) {
                    final scope = scopes[index];
                    return TradeProgressCard(
                      scopeId: scope.id,
                      tradeName: scope.tradeName,
                      tradeColor: scope.tradeColor,
                      onTap: () => context.push(
                        RouteNames.tradeScopeDetailPath(projectId, scope.id),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddScopeStub(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Trade Scope'),
        backgroundColor: const Color(0xFF3949AB),
        foregroundColor: Colors.white,
      ),
    );
  }

  void _showAddScopeStub(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add trade scope — coming soon'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _EmptyScopesState extends StatelessWidget {
  const _EmptyScopesState({required this.onAddScope});

  final VoidCallback onAddScope;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category_outlined,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No trade scopes added',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add trade scopes to track work by trade (electrical, plumbing, framing, etc.)',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAddScope,
              icon: const Icon(Icons.add),
              label: const Text('Add Trade Scope'),
            ),
          ],
        ),
      ),
    );
  }
}
