import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../data/time_entry_dao.dart';
import '../providers/timer_providers.dart';

/// Time tracking section for the Schedule tab of Job Detail.
///
/// Shows all time entry sessions for a job grouped by date with:
/// - Contractor ID, start – end times, duration per row.
/// - "In progress" label with live elapsed time for active sessions.
/// - Per-day subtotals and overall total at the bottom.
/// - For admin role: edit icon per row opens [_AdjustTimeDialog].
///
/// Streamed from [timeEntriesForJobProvider] — offline-first, reactive.
class TimeTrackedSection extends ConsumerWidget {
  final String jobId;

  const TimeTrackedSection({required this.jobId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(timeEntriesForJobProvider(jobId));
    final timerAsync = ref.watch(timerNotifierProvider);
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState is AuthAuthenticated &&
        authState.roles.any((r) => r.name == 'admin');

    final activeElapsed =
        timerAsync.value?.activeJobId == jobId
            ? (timerAsync.value?.elapsedSeconds ?? 0)
            : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Text(
            'Time Tracked',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        entriesAsync.when(
          data: (entries) {
            if (entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No time tracked yet',
                    style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }

            return _TimeEntriesContent(
              entries: entries,
              isAdmin: isAdmin,
              activeElapsed: activeElapsed,
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }
}

// ─── Main content ─────────────────────────────────────────────────────────────

class _TimeEntriesContent extends StatelessWidget {
  final List<TimeEntry> entries;
  final bool isAdmin;
  final int activeElapsed;

  const _TimeEntriesContent({
    required this.entries,
    required this.isAdmin,
    required this.activeElapsed,
  });

  @override
  Widget build(BuildContext context) {
    // Group entries by date string (YYYY-MM-DD key).
    final grouped = <String, List<TimeEntry>>{};
    for (final entry in entries) {
      final key = _dateKey(entry.clockedInAt);
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    // Sort dates newest-first.
    final sortedDates = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    int totalSeconds = 0;
    for (final entry in entries) {
      if (entry.durationSeconds != null) {
        totalSeconds += entry.durationSeconds!;
      }
      if (entry.clockedOutAt == null) {
        totalSeconds += activeElapsed;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final date in sortedDates) ...[
          _DateGroup(
            date: date,
            entries: grouped[date]!,
            isAdmin: isAdmin,
            activeElapsed: activeElapsed,
          ),
          const SizedBox(height: 8),
        ],
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total Tracked',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              _formatDuration(totalSeconds),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ─── Date group ───────────────────────────────────────────────────────────────

class _DateGroup extends StatelessWidget {
  final String date; // YYYY-MM-DD
  final List<TimeEntry> entries;
  final bool isAdmin;
  final int activeElapsed;

  const _DateGroup({
    required this.date,
    required this.entries,
    required this.isAdmin,
    required this.activeElapsed,
  });

  @override
  Widget build(BuildContext context) {
    // Per-day subtotal.
    int daySeconds = 0;
    for (final e in entries) {
      if (e.durationSeconds != null) daySeconds += e.durationSeconds!;
      if (e.clockedOutAt == null) daySeconds += activeElapsed;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDateHeader(date),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            Text(
              _formatDuration(daySeconds),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...entries.map(
          (entry) => _EntryRow(
            entry: entry,
            isAdmin: isAdmin,
            activeElapsed:
                entry.clockedOutAt == null ? activeElapsed : 0,
          ),
        ),
      ],
    );
  }

  String _formatDateHeader(String key) {
    // Parse YYYY-MM-DD
    final parts = key.split('-');
    if (parts.length != 3) return key;
    final year = int.tryParse(parts[0]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 0;
    final day = int.tryParse(parts[2]) ?? 0;
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    if (month < 1 || month > 12) return key;
    return '${months[month - 1]} $day, $year';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ─── Entry row ────────────────────────────────────────────────────────────────

class _EntryRow extends StatelessWidget {
  final TimeEntry entry;
  final bool isAdmin;
  final int activeElapsed;

  const _EntryRow({
    required this.entry,
    required this.isAdmin,
    required this.activeElapsed,
  });

  bool get _isActive => entry.clockedOutAt == null;

  @override
  Widget build(BuildContext context) {
    final startLabel = _formatTime(entry.clockedInAt);
    final endLabel =
        _isActive ? 'In progress' : _formatTime(entry.clockedOutAt!);
    final duration = _isActive
        ? _formatDuration(activeElapsed)
        : _formatDuration(entry.durationSeconds ?? 0);
    final contractorShort = entry.contractorId.length > 8
        ? '...${entry.contractorId.substring(entry.contractorId.length - 8)}'
        : entry.contractorId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contractorShort,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
                Text(
                  '$startLabel — $endLabel',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _isActive
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                ),
              ],
            ),
          ),
          Text(
            duration,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _openAdjustDialog(context),
              visualDensity: VisualDensity.compact,
              tooltip: 'Adjust time entry',
            ),
        ],
      ),
    );
  }

  void _openAdjustDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _AdjustTimeDialog(entry: entry),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ─── Adjust time dialog (admin only) ─────────────────────────────────────────

/// Admin-only dialog to adjust a time entry start/end with required reason.
///
/// Fields:
/// - Start time (hour/minute picker).
/// - End time (hour/minute picker) — disabled for active sessions.
/// - Reason (required TextField).
///
/// On save: appends to the adjustment_log and writes updated entry to Drift.
/// The adjustment_log provides admin audit trail per the TimeEntries schema.
class _AdjustTimeDialog extends ConsumerStatefulWidget {
  final TimeEntry entry;

  const _AdjustTimeDialog({required this.entry});

  @override
  ConsumerState<_AdjustTimeDialog> createState() =>
      _AdjustTimeDialogState();
}

class _AdjustTimeDialogState extends ConsumerState<_AdjustTimeDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  final _reasonController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.fromDateTime(widget.entry.clockedInAt);
    _endTime = widget.entry.clockedOutAt != null
        ? TimeOfDay.fromDateTime(widget.entry.clockedOutAt!)
        : TimeOfDay.now();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adjust Time Entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Start time
            ListTile(
              leading: const Icon(Icons.login_outlined),
              title: const Text('Clock In'),
              subtitle: Text(_startTime.format(context)),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _startTime,
                );
                if (picked != null && mounted) {
                  setState(() => _startTime = picked);
                }
              },
              contentPadding: EdgeInsets.zero,
            ),
            // End time (disabled for active session)
            ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: const Text('Clock Out'),
              subtitle: widget.entry.clockedOutAt == null
                  ? const Text(
                      'Still active — cannot adjust end time',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    )
                  : Text(_endTime.format(context)),
              onTap: widget.entry.clockedOutAt == null
                  ? null
                  : () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _endTime,
                      );
                      if (picked != null && mounted) {
                        setState(() => _endTime = picked);
                      }
                    },
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            // Reason (required)
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Reason (required)',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _save(context),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    if (_reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Reason is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final entry = widget.entry;
      final originalDate = entry.clockedInAt;

      // Build adjusted datetimes using the original date but new times.
      final newStart = DateTime(
        originalDate.year,
        originalDate.month,
        originalDate.day,
        _startTime.hour,
        _startTime.minute,
      );
      DateTime? newEnd;
      if (entry.clockedOutAt != null) {
        newEnd = DateTime(
          originalDate.year,
          originalDate.month,
          originalDate.day,
          _endTime.hour,
          _endTime.minute,
        );
      }

      final now = DateTime.now();
      final authState = ref.read(authNotifierProvider);
      final adjustedBy = authState is AuthAuthenticated
          ? authState.userId
          : 'unknown';

      // Build updated adjustment_log (list-replacement, never in-place append).
      List<dynamic> existingLog;
      try {
        existingLog = jsonDecode(entry.adjustmentLog) as List<dynamic>;
      } catch (_) {
        existingLog = [];
      }
      final newLog = List<dynamic>.from(existingLog)
        ..add({
          'adjustedBy': adjustedBy,
          'originalClockIn': entry.clockedInAt.toIso8601String(),
          'originalClockOut': entry.clockedOutAt?.toIso8601String(),
          'reason': _reasonController.text.trim(),
          'timestamp': now.toIso8601String(),
        });

      final newDuration = newEnd != null
          ? newEnd.difference(newStart).inSeconds
          : entry.durationSeconds;

      // Use the DAO directly — encapsulates both the entity write and the
      // sync_queue entry into one transaction.
      final dao = getIt<TimeEntryDao>();
      await dao.adjustEntry(
        entryId: entry.id,
        newClockIn: newStart,
        newClockOut: newEnd,
        newDuration: newDuration,
        newAdjustmentLog: jsonEncode(newLog),
        newVersion: entry.version + 1,
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save: $e';
        });
      }
    }
  }
}
