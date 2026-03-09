import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/calendar_providers.dart';

/// Multi-day booking configuration wizard.
///
/// Shown after the first-day booking is created when a job's
/// [estimatedDurationMinutes] > 480 (8 hours).
///
/// Flow:
///   1. Shows summary of first-day booking (already created).
///   2. "Additional days" list: each entry has date + start time + end time.
///   3. "Add day" button appends a new entry.
///   4. "Suggest dates" button calls the backend endpoint and pre-fills entries.
///      If offline, the button is disabled.
///   5. Cancel: calls [onCancelled] (undoes the first-day booking) + closes.
///   6. Confirm: calls [onConfirmed] with the list of DayBlocks for remaining days.
///
/// The dialog is opaque and non-dismissible by tapping outside to prevent
/// accidental cancellation after the first-day booking has been created.
class MultiDayWizardDialog extends ConsumerStatefulWidget {
  const MultiDayWizardDialog({
    required this.parentBookingId,
    required this.jobDescription,
    required this.firstDayContractorName,
    required this.firstDayStart,
    required this.firstDayEnd,
    required this.companyId,
    required this.defaultContractorId,
    required this.onConfirmed,
    required this.onCancelled,
    super.key,
  });

  /// ID of the first-day booking already written to Drift.
  final String parentBookingId;

  /// Human-readable job description for the dialog title.
  final String jobDescription;

  /// Name of the contractor selected for the first day.
  final String firstDayContractorName;

  /// Start time of the first-day booking.
  final DateTime firstDayStart;

  /// End time of the first-day booking.
  final DateTime firstDayEnd;

  /// Company ID for API calls.
  final String companyId;

  /// Contractor ID pre-filled for additional days.
  final String defaultContractorId;

  /// Called with the list of DayBlock entries for days 2+.
  final Future<void> Function(List<DayBlock> additionalDays) onConfirmed;

  /// Called when user cancels — should undo the first-day booking.
  final Future<void> Function() onCancelled;

  @override
  ConsumerState<MultiDayWizardDialog> createState() =>
      _MultiDayWizardDialogState();
}

class _MultiDayWizardDialogState
    extends ConsumerState<MultiDayWizardDialog> {
  final List<_DayEntry> _entries = [];
  bool _isLoadingSuggestions = false;
  bool _isConfirming = false;
  bool _isCancelling = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Start with one additional day pre-filled to day after first day
    _entries.add(
      _DayEntry(
        date: widget.firstDayStart.add(const Duration(days: 1)),
        startTime: TimeOfDay(
          hour: widget.firstDayStart.hour,
          minute: widget.firstDayStart.minute,
        ),
        endTime: TimeOfDay(
          hour: widget.firstDayEnd.hour,
          minute: widget.firstDayEnd.minute,
        ),
        contractorId: widget.defaultContractorId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.calendar_month, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Multi-day job',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // First day summary
            _FirstDaySummary(
              jobDescription: widget.jobDescription,
              contractorName: widget.firstDayContractorName,
              start: widget.firstDayStart,
              end: widget.firstDayEnd,
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Additional days section
            Row(
              children: [
                Text(
                  'Additional days',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _isLoadingSuggestions ? null : _fetchSuggestedDates,
                  icon: _isLoadingSuggestions
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 14),
                  label: const Text('Suggest', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Day entries list (scrollable if many)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  return _DayEntryRow(
                    entry: _entries[index],
                    dayIndex: index + 2, // Day 2, 3, ...
                    onChanged: (updated) {
                      setState(() => _entries[index] = updated);
                    },
                    onRemove: _entries.length > 1
                        ? () => setState(() => _entries.removeAt(index))
                        : null,
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Add day button
            OutlinedButton.icon(
              onPressed: _addDay,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add day', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Cancel — undoes the first-day booking
        TextButton(
          onPressed: (_isCancelling || _isConfirming) ? null : _handleCancel,
          child: _isCancelling
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Cancel', style: TextStyle(color: Colors.red)),
        ),

        // Confirm — creates all additional day bookings
        ElevatedButton(
          onPressed: (_isCancelling || _isConfirming) ? null : _handleConfirm,
          child: _isConfirming
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Confirm bookings'),
        ),
      ],
    );
  }

  void _addDay() {
    final lastEntry = _entries.last;
    setState(() {
      _entries.add(
        _DayEntry(
          date: lastEntry.date.add(const Duration(days: 1)),
          startTime: lastEntry.startTime,
          endTime: lastEntry.endTime,
          contractorId: lastEntry.contractorId,
        ),
      );
    });
  }

  /// Fetch suggested dates from backend scheduling API.
  ///
  /// IMPORTANT: Checks internet connectivity before making the API call.
  /// If offline, shows "Offline — enter dates manually" message.
  Future<void> _fetchSuggestedDates() async {
    // Two-phase connectivity check (same pattern as ConnectivityService)
    final hasInternet = await InternetConnection().hasInternetAccess;
    if (!hasInternet) {
      setState(() {
        _errorMessage = 'Offline — enter dates manually';
        _isLoadingSuggestions = false;
      });
      return;
    }

    setState(() {
      _isLoadingSuggestions = true;
      _errorMessage = null;
    });

    try {
      final authState = ref.read(authNotifierProvider);
      if (authState is! AuthAuthenticated) {
        setState(() {
          _errorMessage = 'Not authenticated';
          _isLoadingSuggestions = false;
        });
        return;
      }

      final dioClient = getIt<DioClient>();
      final response = await dioClient.instance.post(
        '/scheduling/suggest-dates',
        data: {
          'parent_booking_id': widget.parentBookingId,
          'company_id': widget.companyId,
          'contractor_id': widget.defaultContractorId,
          'existing_days': _entries.length,
        },
      );

      if (response.statusCode == 200) {
        final suggestions = response.data;
        if (suggestions is List && suggestions.isNotEmpty) {
          setState(() {
            _entries.clear();
            for (final suggestion in suggestions) {
              if (suggestion is Map<String, dynamic>) {
                final startStr = suggestion['start_time'] as String?;
                final endStr = suggestion['end_time'] as String?;
                if (startStr != null && endStr != null) {
                  final start = DateTime.tryParse(startStr);
                  final end = DateTime.tryParse(endStr);
                  if (start != null && end != null) {
                    _entries.add(_DayEntry(
                      date: start,
                      startTime: TimeOfDay.fromDateTime(start),
                      endTime: TimeOfDay.fromDateTime(end),
                      contractorId: suggestion['contractor_id'] as String? ??
                          widget.defaultContractorId,
                    ));
                  }
                }
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('MultiDayWizardDialog: suggest-dates error: $e');
      setState(() {
        _errorMessage = 'Failed to fetch suggestions. Enter dates manually.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingSuggestions = false);
      }
    }
  }

  Future<void> _handleCancel() async {
    setState(() => _isCancelling = true);
    try {
      await widget.onCancelled();
    } catch (e) {
      debugPrint('MultiDayWizardDialog: cancel error: $e');
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleConfirm() async {
    // Validate that all entries have valid time ranges
    for (final entry in _entries) {
      final startMinutes = entry.startTime.hour * 60 + entry.startTime.minute;
      final endMinutes = entry.endTime.hour * 60 + entry.endTime.minute;
      if (endMinutes <= startMinutes) {
        setState(() {
          _errorMessage = 'End time must be after start time for all days';
        });
        return;
      }
    }

    setState(() {
      _isConfirming = true;
      _errorMessage = null;
    });

    try {
      final dayBlocks = _entries.map((entry) {
        final start = DateTime(
          entry.date.year,
          entry.date.month,
          entry.date.day,
          entry.startTime.hour,
          entry.startTime.minute,
        );
        final end = DateTime(
          entry.date.year,
          entry.date.month,
          entry.date.day,
          entry.endTime.hour,
          entry.endTime.minute,
        );
        return DayBlock(
          contractorId: entry.contractorId,
          startTime: start,
          endTime: end,
        );
      }).toList();

      await widget.onConfirmed(dayBlocks);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('MultiDayWizardDialog: confirm error: $e');
      if (mounted) {
        setState(() {
          _isConfirming = false;
          _errorMessage = 'Failed to create bookings. Please try again.';
        });
      }
    }
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _FirstDaySummary extends StatelessWidget {
  const _FirstDaySummary({
    required this.jobDescription,
    required this.contractorName,
    required this.start,
    required this.end,
  });

  final String jobDescription;
  final String contractorName;
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Day 1 — created',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            jobDescription,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            '$contractorName  •  ${_formatDateTime(start)} – ${_formatTime(end)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey[600], fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}  ${_formatTime(dt)}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h:$minute $period';
  }
}

/// Mutable entry for a single additional booking day in the wizard.
class _DayEntry {
  _DayEntry({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.contractorId,
  });

  DateTime date;
  TimeOfDay startTime;
  TimeOfDay endTime;
  String contractorId;

  _DayEntry copyWith({
    DateTime? date,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? contractorId,
  }) {
    return _DayEntry(
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      contractorId: contractorId ?? this.contractorId,
    );
  }
}

/// Row for editing a single additional day entry in the wizard.
class _DayEntryRow extends StatelessWidget {
  const _DayEntryRow({
    required this.entry,
    required this.dayIndex,
    required this.onChanged,
    this.onRemove,
  });

  final _DayEntry entry;
  final int dayIndex;
  final ValueChanged<_DayEntry> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Day $dayIndex',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  color: Colors.red[400],
                ),
            ],
          ),
          const SizedBox(height: 4),

          // Date picker row
          Row(
            children: [
              // Date
              Expanded(
                flex: 2,
                child: _PickerButton(
                  icon: Icons.calendar_today,
                  label: _formatDate(entry.date),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: entry.date,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      onChanged(entry.copyWith(date: picked));
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),

              // Start time
              Expanded(
                child: _PickerButton(
                  icon: Icons.access_time,
                  label: entry.startTime.format(context),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: entry.startTime,
                    );
                    if (picked != null) {
                      onChanged(entry.copyWith(startTime: picked));
                    }
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('–', style: TextStyle(fontSize: 12)),
              ),

              // End time
              Expanded(
                child: _PickerButton(
                  icon: Icons.access_time_filled,
                  label: entry.endTime.format(context),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: entry.endTime,
                    );
                    if (picked != null) {
                      onChanged(entry.copyWith(endTime: picked));
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.grey[600]),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
