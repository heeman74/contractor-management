import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../features/projects/presentation/screens/photo_annotation_screen.dart';

/// Shows a modal bottom sheet for rejecting a task.
///
/// Returns a [Map] with:
/// - `"reason"`: the selected rejection reason code (String, non-null)
/// - `"comment"`: optional free-text comment (String, may be empty)
/// - `"photoPath"`: local path of attached evidence photo (String?, nullable)
/// - `"annotationData"`: annotation JSON string (String?, nullable)
///
/// Returns `null` if the user dismisses the sheet without submitting.
///
/// Usage:
/// ```dart
/// final result = await showRejectionSheet(context);
/// if (result != null) { /* submit rejection */ }
/// ```
Future<Map<String, dynamic>?> showRejectionSheet(BuildContext context) async {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _RejectionForm(),
  );
}

/// The internal rejection form widget rendered inside the bottom sheet.
class _RejectionForm extends StatefulWidget {
  const _RejectionForm();

  @override
  State<_RejectionForm> createState() => _RejectionFormState();
}

class _RejectionFormState extends State<_RejectionForm> {
  static const _reasons = [
    ('rework_needed', 'Rework needed'),
    ('quality_issue', 'Quality does not meet standard'),
    ('wrong_materials', 'Wrong materials used'),
    ('incomplete', 'Work is incomplete'),
    ('safety_concern', 'Safety concern identified'),
    ('other', 'Other (see comment)'),
  ];

  String? _selectedReason;
  final _commentController = TextEditingController();
  String? _photoPath;
  String? _annotationJson;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(BuildContext context) async {
    final picker = ImagePicker();
    final XFile? picked =
        await picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;

    if (!context.mounted) return;

    // Push to photo annotation screen for optional annotation
    final annotationResult = await Navigator.push<String?>(
      context,
      MaterialPageRoute<String?>(
        builder: (_) => PhotoAnnotationScreen(
          localPath: picked.path,
        ),
      ),
    );

    if (!mounted) return;
    // annotationResult may be null (user discarded annotations) or a JSON
    // string. Either way we keep the photo path.
    setState(() {
      _photoPath = picked.path;
      _annotationJson = annotationResult;
    });
  }

  void _removePhoto() {
    setState(() {
      _photoPath = null;
      _annotationJson = null;
    });
  }

  void _submit() {
    final reason = _selectedReason;
    if (reason == null) return;
    Navigator.of(context).pop<Map<String, dynamic>>({
      'reason': reason,
      'comment': _commentController.text.trim(),
      'photoPath': _photoPath,
      'annotationData': _annotationJson,
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reject Task',
              style: textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            // Reason dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedReason,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _reasons
                  .map(
                    (r) => DropdownMenuItem(
                      value: r.$1,
                      child: Text(r.$2),
                    ),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedReason = val),
            ),
            const SizedBox(height: 16),

            // Comment field
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 16),

            // Photo evidence
            if (_photoPath == null)
              OutlinedButton.icon(
                icon: const Icon(Icons.add_a_photo),
                label: const Text('Add Photo Evidence'),
                onPressed: () => _addPhoto(context),
              )
            else
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_photoPath!),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove photo',
                    onPressed: _removePhoto,
                  ),
                ],
              ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedReason != null ? _submit : null,
                child: const Text('Confirm Rejection'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
