import 'package:flutter/material.dart';

import '../../../jobs/data/job_dao.dart';
import '../../../jobs/domain/job_entity.dart';

/// Modal dialog for reporting a delay on a job.
///
/// Enforces both reason text and new ETA date before allowing submission.
/// Offline-capable: writes directly to Drift + sync queue via [JobDao.reportDelay].
/// Does NOT make HTTP calls — sync happens in the background.
///
/// Usage:
/// ```dart
/// final confirmed = await DelayJustificationDialog.show(
///   context: context,
///   jobDao: jobDao,
///   job: job,
///   currentUserId: userId,
/// );
/// if (confirmed) {
///   ScaffoldMessenger.of(context).showSnackBar(...);
/// }
/// ```
class DelayJustificationDialog extends StatefulWidget {
  const DelayJustificationDialog._({
    required this.jobDao,
    required this.job,
    required this.currentUserId,
  });

  final JobDao jobDao;
  final JobEntity job;
  final String currentUserId;

  /// Shows the delay justification dialog and returns true if delay was reported.
  ///
  /// Returns false if the user cancels without submitting.
  static Future<bool> show({
    required BuildContext context,
    required JobDao jobDao,
    required JobEntity job,
    required String currentUserId,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Required fields — no accidental dismiss
      builder: (_) => DelayJustificationDialog._(
        jobDao: jobDao,
        job: job,
        currentUserId: currentUserId,
      ),
    );
    return result ?? false;
  }

  @override
  State<DelayJustificationDialog> createState() =>
      _DelayJustificationDialogState();
}

class _DelayJustificationDialogState extends State<DelayJustificationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  DateTime? _selectedEta;
  bool _isSubmitting = false;
  bool _hasAttemptedSubmit = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.schedule_send, size: 20),
          SizedBox(width: 8),
          Text('Report Delay'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.job.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            // Reason field
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for delay *',
                hintText: 'Describe the reason...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              textInputAction: TextInputAction.newline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Reason is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // ETA date picker
            _EtaDateField(
              selectedEta: _selectedEta,
              initialDate: _defaultInitialDate(),
              onDateSelected: (date) => setState(() => _selectedEta = date),
              hasError: _hasAttemptedSubmit && _selectedEta == null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }

  /// Returns a sensible initial date for the ETA picker.
  ///
  /// Uses scheduledCompletionDate + 1 day if available, otherwise tomorrow.
  DateTime _defaultInitialDate() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    if (widget.job.scheduledCompletionDate != null) {
      final candidate =
          widget.job.scheduledCompletionDate!.add(const Duration(days: 1));
      // Ensure candidate is not in the past
      return candidate.isAfter(tomorrow) ? candidate : tomorrow;
    }
    return tomorrow;
  }

  Future<void> _handleSubmit() async {
    setState(() {
      _isSubmitting = true;
      _hasAttemptedSubmit = true;
    });

    final isFormValid = _formKey.currentState?.validate() ?? false;
    final isEtaSelected = _selectedEta != null;

    if (!isFormValid || !isEtaSelected) {
      setState(() => _isSubmitting = false);
      return;
    }

    try {
      await widget.jobDao.reportDelay(
        jobId: widget.job.id,
        reason: _reasonController.text.trim(),
        newEta: _selectedEta!,
        currentUserId: widget.currentUserId,
        currentVersion: widget.job.version,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to report delay: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

// ─── ETA date picker field ─────────────────────────────────────────────────────

/// ListTile-based date selector for the new ETA field.
///
/// Shows an error indicator if [hasError] is true (no date selected on submit).
class _EtaDateField extends StatelessWidget {
  const _EtaDateField({
    required this.selectedEta,
    required this.initialDate,
    required this.onDateSelected,
    required this.hasError,
  });

  final DateTime? selectedEta;
  final DateTime initialDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'New ETA *',
        border: const OutlineInputBorder(),
        errorText: hasError ? 'New ETA date is required' : null,
      ),
      child: InkWell(
        onTap: () => _pickDate(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: hasError
                    ? errorColor
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedEta != null
                      ? _formatDate(selectedEta!)
                      : 'Select new ETA date',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selectedEta != null
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final lastDate = DateTime(now.year + 1, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(tomorrow) ? initialDate : tomorrow,
      firstDate: tomorrow,
      lastDate: lastDate,
    );

    if (picked != null) {
      onDateSelected(picked);
    }
  }
}
