import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/models/user_role.dart';
import '../providers/project_providers.dart';
import '../widgets/project_card.dart';

/// Project list screen — the Projects tab home.
///
/// Displays projects as a responsive grid of rich cards showing
/// name, status, progress bar, task counts, scope counts, and dates.
///
/// GC/admin role: sees all company projects ordered newest first.
/// Contractor role: sees only projects with an assigned scope.
class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectListProvider);
    final authState = ref.watch(authNotifierProvider);

    final isContractorOnly = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.contractor) &&
        !authState.roles.contains(UserRole.admin);

    return Scaffold(
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading projects: $error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        ),
        data: (projects) {
          if (projects.isEmpty) {
            return _EmptyState(isContractorOnly: isContractorOnly);
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              // Responsive: 2 columns on phones, 3 on tablets
              final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final project = projects[index];
                  return ProjectCard(
                    project: project,
                    onTap: () => context.push(
                      RouteNames.projectDetailPath(project.id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: isContractorOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(RouteNames.aiIntake),
              tooltip: 'New AI Project',
              icon: const Icon(Icons.smart_toy),
              label: const Text('New AI Project'),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isContractorOnly});

  final bool isContractorOnly;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    const heading = 'No projects yet';
    final body = isContractorOnly
        ? "You haven't been assigned to any projects yet."
        : 'Create your first project to get started with trade scope tracking.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              heading,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
