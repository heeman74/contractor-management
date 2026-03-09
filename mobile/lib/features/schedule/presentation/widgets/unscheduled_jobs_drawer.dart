import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/calendar_providers.dart';

// ────────────────────────────────────────────────────────────────────────────
// Unscheduled jobs provider
// ────────────────────────────────────────────────────────────────────────────

/// StreamProvider watching BookingDao.watchUnscheduledJobs for the selected date.
///
/// Returns Job rows (not entities) — the LEFT JOIN query in BookingDao handles
/// filtering jobs with no booking for the current date. Auth-scoped to
/// the current company.
final unscheduledJobsProvider = StreamProvider.autoDispose<List<Job>>((ref) {
  final authState = ref.watch(authNotifierProvider);
  if (authState is! AuthAuthenticated) return const Stream.empty();

  final dao = ref.watch(bookingDaoProvider);
  final selectedDate = ref.watch(calendarDateProvider);
  final companyId = authState.companyId;

  return dao.watchUnscheduledJobs(companyId, selectedDate);
});

// ────────────────────────────────────────────────────────────────────────────
// Widget
// ────────────────────────────────────────────────────────────────────────────

/// Collapsible sidebar drawer showing jobs that have no booking for the current date.
///
/// Displayed as an overlay panel on the right side of the schedule screen.
/// Each job card is wrapped in [LongPressDraggable<BookingDragData>] to enable
/// drag-and-drop scheduling onto contractor lanes.
///
/// Filter controls: status chips, trade type dropdown, client search.
///
/// Data source: [unscheduledJobsProvider] which watches
/// BookingDao.watchUnscheduledJobs (LEFT JOIN — no booking for current date).
class UnscheduledJobsDrawer extends ConsumerStatefulWidget {
  const UnscheduledJobsDrawer({
    required this.laneWidth,
    required this.pixelsPerMinute,
    required this.onClose,
    super.key,
  });

  /// Width used for drag feedback card sizing.
  final double laneWidth;

  /// Scale factor used for drag feedback card height sizing.
  final double pixelsPerMinute;

  /// Called when the user taps the close/collapse button.
  final VoidCallback onClose;

  @override
  ConsumerState<UnscheduledJobsDrawer> createState() =>
      _UnscheduledJobsDrawerState();
}

class _UnscheduledJobsDrawerState
    extends ConsumerState<UnscheduledJobsDrawer> {
  final TextEditingController _searchController = TextEditingController();

  /// Active status filter. Null = show all.
  String? _statusFilter;

  /// Active trade type filter. Null = show all.
  String? _tradeFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(unscheduledJobsProvider);
    final theme = Theme.of(context);

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
        border: Border(
          left: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        children: [
          // Header
          _DrawerHeader(onClose: widget.onClose),

          // Filter bar
          _FilterBar(
            searchController: _searchController,
            statusFilter: _statusFilter,
            tradeFilter: _tradeFilter,
            onStatusChanged: (status) =>
                setState(() => _statusFilter = status),
            onTradeChanged: (trade) =>
                setState(() => _tradeFilter = trade),
            onSearchChanged: (_) => setState(() {}),
          ),

          const Divider(height: 1),

          // Job list
          Expanded(
            child: jobsAsync.when(
              data: (jobs) {
                final filtered = _applyFilters(jobs);
                if (filtered.isEmpty) {
                  return _EmptyState(
                    hasJobs: jobs.isNotEmpty,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final job = filtered[index];
                    return _DraggableJobCard(
                      job: job,
                      laneWidth: widget.laneWidth,
                      pixelsPerMinute: widget.pixelsPerMinute,
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Error loading jobs',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Job> _applyFilters(List<Job> jobs) {
    var filtered = jobs;

    if (_statusFilter != null) {
      filtered =
          filtered.where((j) => j.status == _statusFilter).toList();
    }

    if (_tradeFilter != null) {
      filtered =
          filtered.where((j) => j.tradeType == _tradeFilter).toList();
    }

    final searchText = _searchController.text.trim().toLowerCase();
    if (searchText.isNotEmpty) {
      filtered = filtered
          .where((j) =>
              j.description.toLowerCase().contains(searchText) ||
              (j.clientId?.toLowerCase().contains(searchText) ?? false))
          .toList();
    }

    return filtered;
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.format_list_bulleted, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Unscheduled Jobs',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchController,
    required this.statusFilter,
    required this.tradeFilter,
    required this.onStatusChanged,
    required this.onTradeChanged,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final String? statusFilter;
  final String? tradeFilter;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onTradeChanged;
  final ValueChanged<String> onSearchChanged;

  static const _statuses = ['quote', 'scheduled'];
  static const _tradeTypes = [
    'builder',
    'electrician',
    'plumber',
    'hvac',
    'painter',
    'carpenter',
    'roofer',
    'landscaper',
    'general',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search field
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Search jobs...',
              prefixIcon: Icon(Icons.search, size: 16),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),

          // Status chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: statusFilter == null,
                  onTap: () => onStatusChanged(null),
                ),
                ..._statuses.map(
                  (s) => _FilterChip(
                    label: s[0].toUpperCase() + s.substring(1),
                    selected: statusFilter == s,
                    onTap: () => onStatusChanged(statusFilter == s ? null : s),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Trade type dropdown
          DropdownButtonFormField<String?>(
            initialValue: tradeFilter,
            decoration: const InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              border: OutlineInputBorder(),
              hintText: 'All trades',
            ),
            style: const TextStyle(fontSize: 12, color: Colors.black),
            items: [
              const DropdownMenuItem<String?>(
                child: Text('All trades', style: TextStyle(fontSize: 12)),
              ),
              ..._tradeTypes.map(
                (t) => DropdownMenuItem<String?>(
                  value: t,
                  child: Text(
                    t[0].toUpperCase() + t.substring(1),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
            onChanged: onTradeChanged,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color:
                selected ? theme.colorScheme.primary : Colors.grey[700],
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// A draggable job card for the unscheduled jobs drawer.
///
/// Wrapped in [LongPressDraggable<BookingDragData>] with haptic feedback.
/// The feedback widget is a Material-elevated mini card matching the
/// target slot dimensions.
class _DraggableJobCard extends StatelessWidget {
  const _DraggableJobCard({
    required this.job,
    required this.laneWidth,
    required this.pixelsPerMinute,
  });

  final Job job;
  final double laneWidth;
  final double pixelsPerMinute;

  @override
  Widget build(BuildContext context) {
    final durationMinutes = job.estimatedDurationMinutes ?? 60;
    final feedbackHeight =
        (durationMinutes * pixelsPerMinute).clamp(40.0, 120.0);

    final cardContent = _JobCardContent(job: job);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LongPressDraggable<BookingDragData>(
        data: BookingDragData(
          jobId: job.id,
          durationMinutes: durationMinutes,
        ),
        onDragStarted: () {
          HapticFeedback.mediumImpact();
        },
        feedback: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: laneWidth.clamp(120.0, 200.0),
            height: feedbackHeight,
            child: _FeedbackCard(job: job, height: feedbackHeight),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: cardContent,
        ),
        child: cardContent,
      ),
    );
  }
}

class _JobCardContent extends StatelessWidget {
  const _JobCardContent({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(job.status);

    return Container(
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  job.status,
                  style: TextStyle(
                    fontSize: 9,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.construction,
                size: 11,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 3),
              Text(
                job.tradeType,
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
              if (job.estimatedDurationMinutes != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.schedule, size: 11, color: Colors.grey[600]),
                const SizedBox(width: 3),
                Text(
                  _formatDuration(job.estimatedDurationMinutes!),
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
          // Drag hint
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.drag_indicator,
                  size: 12, color: Colors.grey[400]),
              const SizedBox(width: 2),
              Text(
                'Hold to drag',
                style: TextStyle(fontSize: 9, color: Colors.grey[400]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Color _statusColor(String status) {
    return switch (status) {
      'quote' => Colors.grey,
      'scheduled' => Colors.blue,
      _ => Colors.grey,
    };
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.job, required this.height});
  final Job job;
  final double height;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(job.status);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        border: Border(
          left: BorderSide(color: statusColor, width: 4),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: statusColor.withValues(alpha: 0.9),
            ),
          ),
          if (height > 40) ...[
            const SizedBox(height: 2),
            Text(
              job.tradeType,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'quote' => Colors.grey,
      'scheduled' => Colors.blue,
      _ => Colors.grey,
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasJobs});
  final bool hasJobs;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 40,
            color: Colors.green[400],
          ),
          const SizedBox(height: 12),
          Text(
            hasJobs ? 'No jobs match filters' : 'All jobs scheduled',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (!hasJobs) ...[
            const SizedBox(height: 6),
            Text(
              'Drag jobs from here\nto schedule them',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
