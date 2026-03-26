import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../domain/billing_milestone_entity.dart';
import '../providers/billing_milestone_providers.dart';

/// Modal bottom sheet for creating a new billing milestone.
///
/// Presents a form with:
/// - name (required text field)
/// - percentage (numeric, 0-100 validation)
/// - description (optional text field)
///
/// On submission, creates a [BillingMilestoneEntity] with a generated UUID and
/// calls [createMilestoneAction] to write to the local Drift database (which
/// enqueues a CREATE sync item for the backend).
///
/// Closes the sheet on successful creation.
class CreateMilestoneSheet extends ConsumerStatefulWidget {
  const CreateMilestoneSheet({
    required this.scopeId,
    required this.existingCount,
    super.key,
  });

  /// ID of the trade scope this milestone belongs to.
  final String scopeId;

  /// Number of existing milestones — used to set the [sortOrder] for the new one.
  final int existingCount;

  @override
  ConsumerState<CreateMilestoneSheet> createState() =>
      _CreateMilestoneSheetState();
}

class _CreateMilestoneSheetState extends ConsumerState<CreateMilestoneSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _percentageController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _percentageController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthAuthenticated) {
      debugPrint('[CreateMilestoneSheet] Not authenticated — cannot create milestone');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final entity = BillingMilestoneEntity(
        id: const Uuid().v4(),
        companyId: authState.companyId,
        tradeScopeId: widget.scopeId,
        name: _nameController.text.trim(),
        percentage: double.parse(_percentageController.text.trim()),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        isInvoiced: false,
        sortOrder: widget.existingCount,
        version: 1,
        createdAt: now,
        updatedAt: now,
      );

      await createMilestoneAction(ref, entity);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[CreateMilestoneSheet] Error creating milestone: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create milestone.')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Billing Milestone',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),

            // Name field (required)
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Milestone Name',
                hintText: 'e.g. Mobilisation, Framing Complete',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Percentage field (required, 0-100)
            TextFormField(
              controller: _percentageController,
              decoration: const InputDecoration(
                labelText: 'Percentage (%)',
                hintText: '25',
                border: OutlineInputBorder(),
                suffixText: '%',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Percentage is required';
                }
                final parsed = double.tryParse(val.trim());
                if (parsed == null) {
                  return 'Enter a valid number';
                }
                if (parsed <= 0 || parsed > 100) {
                  return 'Must be between 0 and 100 (exclusive)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Description field (optional)
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Additional details about this milestone',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _submit,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add Milestone'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
