import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_status_provider.dart';

/// Sync status subtitle widget for the app bar.
///
/// Displays the current sync state below the main app bar title. Always
/// visible — does not fade or disappear (user decision: subtitle stays
/// on screen at all times).
///
/// States and their display:
/// - [SyncState.allSynced]: green check icon + "All synced"
/// - [SyncState.pending]:   sync icon + "N item(s) pending"
/// - [SyncState.syncing]:   animated rotation sync icon + "Syncing M of N..."
/// - [SyncState.offline]:   wifi_off icon + "Offline"
///
/// Subtle styling: small text (fontSize 11), slightly muted color — this is
/// secondary information that should not compete with the main app bar title.
///
/// User decision: no toast, no banner on connectivity loss — only the subtle
/// wifi_off icon + "Offline" text in the subtitle area.
class SyncStatusSubtitle extends ConsumerWidget {
  const SyncStatusSubtitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncAsync = ref.watch(syncStatusProvider);

    return syncAsync.when(
      loading: () => _SubtitleRow(
        icon: Icons.check_circle_outline,
        label: 'All synced',
        color: Colors.green.shade600,
      ),
      error: (_, __) => _SubtitleRow(
        icon: Icons.error_outline,
        label: 'Sync error',
        color: Colors.orange.shade700,
      ),
      data: (status) => _buildFromStatus(context, status),
    );
  }

  Widget _buildFromStatus(BuildContext context, SyncStatus status) {
    switch (status.state) {
      case SyncState.allSynced:
        return _SubtitleRow(
          icon: Icons.check_circle_outline,
          label: 'All synced',
          color: Colors.green.shade600,
        );

      case SyncState.pending:
        return _SubtitleRow(
          icon: Icons.sync,
          label: status.subtitle, // "N item(s) pending"
          color: Colors.orange.shade700,
        );

      case SyncState.syncing:
        return _AnimatedSyncRow(label: status.subtitle); // "Syncing M of N..."

      case SyncState.offline:
        return _SubtitleRow(
          icon: Icons.wifi_off,
          label: 'Offline',
          color: Colors.grey.shade600,
        );
    }
  }
}

/// A static icon + label row for the sync subtitle.
class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// A sync row with a continuously rotating sync icon — used during active sync.
class _AnimatedSyncRow extends StatefulWidget {
  const _AnimatedSyncRow({required this.label});

  final String label;

  @override
  State<_AnimatedSyncRow> createState() => _AnimatedSyncRowState();
}

class _AnimatedSyncRowState extends State<_AnimatedSyncRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotationTransition(
          turns: _controller,
          child: Icon(
            Icons.sync,
            size: 11,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
