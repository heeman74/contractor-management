import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart'
    show Project, CostEntry;
import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/finance/presentation/providers/cost_providers.dart';
import '../../../../features/finance/presentation/widgets/cost_breakdown_summary.dart';
import '../../../../features/finance/presentation/widgets/cost_entry_card.dart';
import '../../../../shared/models/user_role.dart';
import '../providers/project_providers.dart';
import '../widgets/billing_summary_card.dart';
import '../widgets/flag_capture_sheet.dart';
import '../widgets/project_status_badge.dart';
import '../widgets/site_walk_flag_section.dart';
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
    final authState = ref.watch(authNotifierProvider);

    // Extract project from cached async state without triggering loading indicator
    Project? project;
    if (projectsAsync is AsyncData<List<Project>>) {
      project = projectsAsync.value
          .where((p) => p.id == projectId)
          .firstOrNull;
    }

    final projectName = project?.name ?? 'Project';
    final projectStatus = project?.status ?? 'draft';

    // GC/admin check: admin is the GC role in this app
    final isGcOrAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);

    // Costs rollup — finance.view only (D-06).
    final canViewFinance = ref.watch(financePermissionProvider).canView;

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
          // Chat button — Phase 23 real-time chat
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Messages',
            onPressed: () =>
                context.push(RouteNames.chatPath(projectId)),
          ),
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
                child: ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  children: [
                    // Trade scope progress cards
                    ...scopes.map((scope) => TradeProgressCard(
                          scopeId: scope.id,
                          tradeName: scope.tradeName,
                          tradeColor: scope.tradeColor,
                          onTap: () => context.push(
                            RouteNames.tradeScopeDetailPath(
                                projectId, scope.id),
                          ),
                        )),
                    // Site walk flags section — collapsible, GC-aware
                    SiteWalkFlagSection(
                      projectId: projectId,
                      isGcOrAdmin: isGcOrAdmin,
                    ),

                    // ── Phase 25: Billing summary cards (GC/admin only) ──
                    if (isGcOrAdmin) ...[
                      // quote-summary
                      BillingSummaryCard(
                        projectId: projectId,
                        type: BillingSummaryType.quote,
                      ),
                      // invoice-summary
                      BillingSummaryCard(
                        projectId: projectId,
                        type: BillingSummaryType.invoice,
                      ),
                    ],

                    // ── Costs rollup (finance.view only — D-06) ─────────
                    if (canViewFinance)
                      _ProjectCostRollupSection(projectId: projectId),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Flag Issue button — only for GC/admin
          if (isGcOrAdmin) ...[
            FloatingActionButton.extended(
              heroTag: 'flagIssue',
              onPressed: () => showFlagCaptureFlow(context, projectId, ref),
              icon: const Icon(Icons.flag),
              label: const Text('Flag Issue'),
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            const SizedBox(height: 8),
          ],
          // Add Trade Scope button
          FloatingActionButton.extended(
            heroTag: 'addScope',
            onPressed: () => _showAddScopeStub(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Trade Scope'),
            backgroundColor: const Color(0xFF3949AB),
            foregroundColor: Colors.white,
          ),
        ],
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

/// Read-only aggregated Costs rollup for a project — finance.view only.
///
/// Shows the authoritative backend-computed total ([costRollupTotalProvider]
/// — never a locally-summed estimate, per 31-RESEARCH.md Pitfall 5) plus the
/// itemized cost entries ([costRollupForProjectProvider]). Create actions
/// stay on the job/trade-scope detail screens (Claude's-Discretion scope
/// trim documented in 31-CONTEXT.md — a read-only rollup is the minimum
/// here).
class _ProjectCostRollupSection extends ConsumerWidget {
  const _ProjectCostRollupSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAsync = ref.watch(costRollupTotalProvider(projectId));
    final breakdownAsync = ref.watch(projectCostBreakdownProvider(projectId));
    final entriesAsync = ref.watch(costRollupForProjectProvider(projectId));
    final entries = entriesAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <CostEntry>[],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Costs',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              totalAsync.when(
                loading: () => const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (total) => Text(
                  total == null ? '—' : r'$' '$total',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        CostBreakdownSummary(
          breakdown: breakdownAsync.value,
          variant: CostBreakdownVariant.project,
          isLoading: breakdownAsync.isLoading,
          isUnavailable: breakdownAsync.hasError,
        ),
        const Divider(indent: 16, endIndent: 16),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text(
              'No costs recorded yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          ...entries.map((entry) => CostEntryCard(entry: entry)),
        const SizedBox(height: 16),
      ],
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
