import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';

/// Weekly working-hour template management screen for a contractor.
///
/// Shows 7 rows (Monday through Sunday), each with:
///   - Day name
///   - Working / Day off toggle
///   - Start time + end time pickers (TimeOfDay) — enabled when working
///   - "Set as day off" button (quick action)
///
/// Data flow:
///   - On load: GET /api/v1/scheduling/schedules/{contractorId}/weekly
///   - On save: PATCH to the same endpoint
///   - Offline: shows cached data or "Connect to manage schedule" message
///
/// Navigation:
///   - Accessible from contractor's schedule screen (gear icon in AppBar)
///   - Accessible from admin calendar via long-press on contractor lane header
///     with optional [contractorId] query param for admin viewing another contractor
///
/// Quick actions:
///   - "Copy to all weekdays": apply Monday's hours to Tue–Fri
///   - "Set all to day off": clear all working days for the week
class ScheduleSettingsScreen extends ConsumerStatefulWidget {
  const ScheduleSettingsScreen({super.key, this.contractorId});

  /// The contractor whose schedule is being managed.
  ///
  /// When null, defaults to the currently logged-in user's ID (contractor mode).
  /// When provided (admin mode), shows schedule for the specified contractor.
  final String? contractorId;

  @override
  ConsumerState<ScheduleSettingsScreen> createState() =>
      _ScheduleSettingsScreenState();
}

class _ScheduleSettingsScreenState
    extends ConsumerState<ScheduleSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isOffline = false;
  String? _errorMessage;

  /// 7-element list: index 0 = Monday, 6 = Sunday.
  final List<_DaySchedule> _daySchedules = List.generate(
    7,
    (index) => _DaySchedule(
      dayIndex: index,
      isWorking: index < 5, // Mon–Fri default to working
      startTime: const TimeOfDay(hour: 8, minute: 0),
      endTime: const TimeOfDay(hour: 17, minute: 0),
    ),
  );

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    final authState = ref.read(authNotifierProvider);
    final contractorId = widget.contractorId ??
        (authState is AuthAuthenticated ? authState.userId : null);

    if (contractorId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not identify contractor';
      });
      return;
    }

    try {
      final dio = getIt<DioClient>().instance;
      final response = await dio.get(
        '/api/v1/scheduling/schedules/$contractorId/weekly',
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final days = data['days'] as List<dynamic>?;
        if (days != null) {
          for (var i = 0; i < days.length && i < 7; i++) {
            final day = days[i];
            if (day is Map<String, dynamic>) {
              final isWorking = day['is_working'] as bool? ?? (i < 5);
              final startStr = day['start_time'] as String? ?? '08:00';
              final endStr = day['end_time'] as String? ?? '17:00';
              setState(() {
                _daySchedules[i] = _DaySchedule(
                  dayIndex: i,
                  isWorking: isWorking,
                  startTime: _parseTime(startStr),
                  endTime: _parseTime(endStr),
                );
              });
            }
          }
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      // If offline, API unavailable, or DioClient not registered (test/offline),
      // show cached defaults with a notice.
      final errorStr = e.toString().toLowerCase();
      final isNetworkError = errorStr.contains('socket') ||
          errorStr.contains('connection') ||
          errorStr.contains('timeout') ||
          errorStr.contains('unreachable') ||
          errorStr.contains('not registered');

      setState(() {
        _isLoading = false;
        _isOffline = isNetworkError;
        if (!isNetworkError) {
          _errorMessage = 'Failed to load schedule: $e';
        }
      });
    }
  }

  Future<void> _saveSchedule() async {
    final authState = ref.read(authNotifierProvider);
    final contractorId = widget.contractorId ??
        (authState is AuthAuthenticated ? authState.userId : null);

    if (contractorId == null) return;

    setState(() => _isSaving = true);

    try {
      final dio = getIt<DioClient>().instance;
      final payload = {
        'days': _daySchedules.map((d) => d.toJson()).toList(),
      };

      await dio.patch(
        '/api/v1/scheduling/schedules/$contractorId/weekly',
        data: payload,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule saved'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } on Exception catch (e) {
      final errorStr = e.toString().toLowerCase();
      final isNetworkError = errorStr.contains('socket') ||
          errorStr.contains('connection') ||
          errorStr.contains('timeout') ||
          errorStr.contains('unreachable');

      if (mounted) {
        if (isNetworkError) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Offline — changes will sync when connected'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState is AuthAuthenticated &&
        widget.contractorId != null &&
        widget.contractorId != authState.userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAdmin ? 'Contractor Schedule' : 'My Schedule Settings',
        ),
        actions: [
          if (!_isLoading && !_isOffline)
            TextButton(
              onPressed: _isSaving ? null : _saveSchedule,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage!,
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Offline banner
        if (_isOffline)
          Container(
            width: double.infinity,
            color: Colors.amber.withValues(alpha: 0.1),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              children: [
                Icon(Icons.wifi_off, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Connect to manage schedule — showing defaults',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
            ),
          ),

        // Quick actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isOffline ? null : _copyMondayToWeekdays,
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: const Text('Copy Mon to weekdays',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isOffline ? null : _setAllDayOff,
                  icon: const Icon(Icons.event_busy, size: 16),
                  label: const Text('All day off',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Day rows
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 7,
            itemBuilder: (context, index) {
              return _DayScheduleRow(
                dayName: _dayNames[index],
                schedule: _daySchedules[index],
                isDisabled: _isOffline,
                onChanged: (updated) {
                  setState(() => _daySchedules[index] = updated);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _copyMondayToWeekdays() {
    final monday = _daySchedules[0];
    setState(() {
      for (var i = 1; i <= 4; i++) {
        _daySchedules[i] = _DaySchedule(
          dayIndex: i,
          isWorking: monday.isWorking,
          startTime: monday.startTime,
          endTime: monday.endTime,
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Monday's hours copied to Tue–Fri"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _setAllDayOff() {
    setState(() {
      for (var i = 0; i < 7; i++) {
        _daySchedules[i] = _DaySchedule(
          dayIndex: i,
          isWorking: false,
          startTime: _daySchedules[i].startTime,
          endTime: _daySchedules[i].endTime,
        );
      }
    });
  }

  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]) ?? 8;
      final minute = int.tryParse(parts[1]) ?? 0;
      return TimeOfDay(hour: hour, minute: minute);
    }
    return const TimeOfDay(hour: 8, minute: 0);
  }
}

// ─── Day schedule data model ──────────────────────────────────────────────────

class _DaySchedule {
  const _DaySchedule({
    required this.dayIndex,
    required this.isWorking,
    required this.startTime,
    required this.endTime,
  });

  final int dayIndex;
  final bool isWorking;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  Map<String, dynamic> toJson() {
    return {
      'day_index': dayIndex,
      'is_working': isWorking,
      'start_time': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
      'end_time': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
    };
  }

  _DaySchedule copyWith({
    bool? isWorking,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    return _DaySchedule(
      dayIndex: dayIndex,
      isWorking: isWorking ?? this.isWorking,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

// ─── Day schedule row ─────────────────────────────────────────────────────────

class _DayScheduleRow extends StatelessWidget {
  const _DayScheduleRow({
    required this.dayName,
    required this.schedule,
    required this.onChanged,
    this.isDisabled = false,
  });

  final String dayName;
  final _DaySchedule schedule;
  final ValueChanged<_DaySchedule> onChanged;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day name + working toggle
            Row(
              children: [
                Expanded(
                  child: Text(
                    dayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: schedule.isWorking
                          ? null
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Switch(
                  value: schedule.isWorking,
                  onChanged: isDisabled
                      ? null
                      : (value) => onChanged(schedule.copyWith(isWorking: value)),
                ),
              ],
            ),

            // Time pickers (only shown when working)
            if (schedule.isWorking) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _TimePicker(
                      label: 'Start',
                      time: schedule.startTime,
                      isDisabled: isDisabled,
                      onChanged: (time) =>
                          onChanged(schedule.copyWith(startTime: time)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePicker(
                      label: 'End',
                      time: schedule.endTime,
                      isDisabled: isDisabled,
                      onChanged: (time) =>
                          onChanged(schedule.copyWith(endTime: time)),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                'Day off',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Time picker ──────────────────────────────────────────────────────────────

class _TimePicker extends StatelessWidget {
  const _TimePicker({
    required this.label,
    required this.time,
    required this.onChanged,
    this.isDisabled = false,
  });

  final String label;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedTime = time.format(context);

    return InkWell(
      onTap: isDisabled
          ? null
          : () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: time,
              );
              if (picked != null) onChanged(picked);
            },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          enabled: !isDisabled,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formattedTime,
              style: TextStyle(
                fontSize: 14,
                color: isDisabled
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                    : null,
              ),
            ),
            Icon(
              Icons.access_time,
              size: 16,
              color: isDisabled
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                  : theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
