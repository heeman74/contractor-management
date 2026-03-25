import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/project_providers.dart';

/// Collapsible section showing site walk flags for a project.
///
/// Shows all open/resolved flags in an [ExpansionTile]. Each flag row
/// has a severity dot, description, and (for GC/admin on open flags) a
/// "Convert to Punch Item" button that calls [SiteWalkFlagDao.convertFlag]
/// atomically via a Drift transaction.
///
/// Usage (embed in ProjectDetailScreen CustomScrollView):
/// ```dart
/// SiteWalkFlagSection(projectId: project.id, isGcOrAdmin: isGcOrAdmin)
/// ```
class SiteWalkFlagSection extends ConsumerWidget {
  const SiteWalkFlagSection({
    required this.projectId,
    required this.isGcOrAdmin,
    super.key,
  });

  final String projectId;
  final bool isGcOrAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagsAsync = ref.watch(flagsForProjectProvider(projectId));

    return flagsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (flags) {
        final count = flags.length;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ExpansionTile(
            leading: const Icon(Icons.flag_outlined),
            title: Row(
              children: [
                const Text('Site Walk Flags'),
                const SizedBox(width: 8),
                Chip(
                  label: Text('$count'),
                  backgroundColor: Colors.grey.shade600,
                  labelStyle: const TextStyle(color: Colors.white),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            children: [
              if (flags.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No flags yet',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap "Flag Issue" during a site walk to document problems.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: flags.length,
                  itemBuilder: (context, index) {
                    final flag = flags[index];
                    return _FlagListTile(
                      flag: flag,
                      isGcOrAdmin: isGcOrAdmin,
                      projectId: projectId,
                      ref: ref,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FlagListTile extends StatelessWidget {
  const _FlagListTile({
    required this.flag,
    required this.isGcOrAdmin,
    required this.projectId,
    required this.ref,
  });

  final SiteWalkFlag flag;
  final bool isGcOrAdmin;
  final String projectId;
  final WidgetRef ref;

  Color _severityColor(String severity) {
    return switch (severity) {
      'high' || 'critical' => const Color(0xFFD32F2F),
      'medium' => const Color(0xFFF57C00),
      _ => const Color(0xFF9E9E9E),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _severityColor(flag.severity),
        ),
      ),
      title: Text(
        flag.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: (isGcOrAdmin && flag.status == 'open')
          ? TextButton(
              onPressed: () => _convertToPunch(context),
              child: const Text('Convert to Punch Item'),
            )
          : null,
    );
  }

  Future<void> _convertToPunch(BuildContext context) async {
    // Ask for a confirmation before converting
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convert to Punch Item?'),
        content: Text(
          'This will mark the flag as converted and create a punch list item '
          'for: "${flag.description}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Build the punch list item companion from the flag's data
    final authState = ref.read(authNotifierProvider);
    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';
    final userId = authState is AuthAuthenticated ? authState.userId : '';

    final punchItem = PunchListItemsCompanion.insert(
      id: Value(const Uuid().v4()),
      companyId: companyId,
      projectId: projectId,
      tradeScopeId: '',
      // tradeScopeId left empty here; full implementation would show
      // a scope picker dialog. For now defaults to '' to satisfy the
      // non-null constraint — scope assignment can be done post-creation.
      createdBy: userId,
      description: flag.description,
      priority: const Value('medium'),
      status: const Value('open'),
      sourceFlagId: Value(flag.id),
      photoUrl: Value(flag.photoUrl),
      annotationData: Value(flag.annotationData),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      final dao = ref.read(siteWalkFlagDaoProvider);
      await dao.convertFlag(flag.id, punchItem);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flag converted to punch list item.')),
        );
      }
    } catch (e) {
      debugPrint('[SiteWalkFlagSection] Convert error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to convert flag. Please try again.')),
        );
      }
    }
  }
}
