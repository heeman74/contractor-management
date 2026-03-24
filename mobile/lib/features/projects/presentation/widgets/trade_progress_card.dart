import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/project_providers.dart';

// ---------------------------------------------------------------------------
// Progress model
// ---------------------------------------------------------------------------

/// Combined task progress counts for a trade scope.
class _ScopeProgress {
  const _ScopeProgress({required this.total, required this.completed});
  final int total;
  final int completed;

  double get fraction => total > 0 ? completed / total : 0.0;

  bool get isEmpty => total == 0;
  bool get isComplete => total > 0 && completed == total;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Streams combined [_ScopeProgress] (total + completed) for a trade scope.
///
/// Uses two FutureProviders combined via a StreamProvider wrapper.
/// Auto-disposed when the card leaves the tree.
///
/// NOTE: GetIt<->Riverpod tradeoff documented — DAO accessed via taskDaoProvider.
final tradeScopeProgressProvider = StreamProvider.autoDispose
    .family<_ScopeProgress, String>((ref, scopeId) {
  final dao = ref.watch(taskDaoProvider);
  // Watch the tasks stream and map to counts — reactive to Drift DB changes.
  return dao.watchTasksByScope(scopeId).asyncMap((tasks) async {
    final total = tasks.length;
    final completed = tasks.where((t) => t.status == 'complete').length;
    return _ScopeProgress(total: total, completed: completed);
  });
});

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// GC progress card for a single trade scope.
///
/// Displays:
/// - Colored dot + trade name (semibold) + "X/Y tasks" count
/// - Color-threshold LinearProgressIndicator:
///   - 0–33%: purple  (#424299)
///   - 34–66%: blue   (#2563EB)
///   - 67–99%: sky    (#38BDF8)
///   - 100%:   green  (#388E3C)
/// - Contractor name row with last activity placeholder
/// - Green checkmark badge when 100% complete
///
/// Per UI-SPEC and D-15 requirement for GC trade monitoring.
class TradeProgressCard extends ConsumerWidget {
  const TradeProgressCard({
    required this.scopeId,
    required this.tradeName,
    required this.tradeColor,
    required this.onTap,
    this.contractorName,
    super.key,
  });

  /// Trade scope ID — used to look up live task counts.
  final String scopeId;

  /// Display name of the trade (e.g. "Electrical").
  final String tradeName;

  /// Trade brand color as a CSS hex string (e.g. "#3F51B5").
  final String tradeColor;

  /// Assigned contractor's display name, or null if unassigned.
  final String? contractorName;

  /// Called when the card is tapped — navigate to read-only scope task list.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final progressAsync = ref.watch(tradeScopeProgressProvider(scopeId));

    final color = _hexToColor(tradeColor);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Semantics(
        label: progressAsync.when(
          data: (p) =>
              '$tradeName: ${p.completed} of ${p.total} tasks complete',
          loading: () => '$tradeName: Loading progress',
          error: (_, __) => '$tradeName: Error loading progress',
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: progressAsync.when(
              loading: () => _buildContent(
                context,
                textTheme: textTheme,
                colorScheme: colorScheme,
                dotColor: color,
                progress: const _ScopeProgress(total: 0, completed: 0),
                isLoading: true,
              ),
              error: (error, _) => _buildContent(
                context,
                textTheme: textTheme,
                colorScheme: colorScheme,
                dotColor: color,
                progress: const _ScopeProgress(total: 0, completed: 0),
              ),
              data: (progress) => _buildContent(
                context,
                textTheme: textTheme,
                colorScheme: colorScheme,
                dotColor: color,
                progress: progress,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required TextTheme textTheme,
    required ColorScheme colorScheme,
    required Color dotColor,
    required _ScopeProgress progress,
    bool isLoading = false,
  }) {
    final progressColor = _progressColor(progress.fraction);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: dot + trade name + spacer + task count + (optional checkmark)
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tradeName,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (progress.isComplete)
              const Icon(
                Icons.check_circle,
                size: 16,
                color: Color(0xFF388E3C),
              ),
            if (progress.isComplete) const SizedBox(width: 4),
            if (!isLoading)
              Text(
                '${progress.completed}/${progress.total} tasks',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            if (isLoading)
              Text(
                '…',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),

        const SizedBox(height: 8),

        // Row 2: LinearProgressIndicator with color threshold
        if (progress.isEmpty)
          Text(
            'No activity yet',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.4),
              fontStyle: FontStyle.italic,
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 6,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              backgroundColor: const Color(0xFFF5F5F5),
              semanticsLabel:
                  '${progress.completed} of ${progress.total} tasks complete',
            ),
          ),

        const SizedBox(height: 8),

        // Row 3: contractor name + last activity
        Row(
          children: [
            Expanded(
              child: contractorName != null
                  ? Text(
                      _abbreviateName(contractorName!),
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      'No contractor assigned',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  /// Returns the LinearProgressIndicator color based on completion fraction.
  ///
  /// Thresholds per UI-SPEC:
  /// - 0–33%: purple (chart-5 equivalent)
  /// - 34–66%: blue (chart-2)
  /// - 67–99%: sky blue (chart-1)
  /// - 100%: green-600
  static Color _progressColor(double fraction) {
    if (fraction >= 1.0) return const Color(0xFF388E3C); // green-600
    if (fraction >= 0.67) return const Color(0xFF38BDF8); // sky blue
    if (fraction >= 0.34) return const Color(0xFF2563EB); // blue
    return const Color(0xFF424299); // purple
  }

  /// Abbreviates a full name to "First L." format.
  ///
  /// e.g. "John Doe" → "John D."
  /// e.g. "John" → "John"
  static String _abbreviateName(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first} ${parts[1][0].toUpperCase()}.';
    }
    return name;
  }

  /// Parse a hex color string to a [Color].
  static Color _hexToColor(String hex) {
    try {
      final cleaned = hex.replaceAll('#', '');
      final value = int.parse(cleaned, radix: 16);
      return Color(0xFF000000 | value);
    } catch (_) {
      return const Color(0xFF9E9E9E);
    }
  }
}
