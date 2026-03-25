import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/project_providers.dart';
import '../screens/photo_annotation_screen.dart';

/// Camera-first flag capture flow per D-09.
///
/// Opens the camera **immediately** on entry — no choice dialog, camera
/// first. If the user cancels the camera, the flag form opens without a
/// photo (description-only fallback). If they take a photo, it is
/// optionally annotated before opening the flag form with the photo
/// pre-populated.
///
/// Usage:
/// ```dart
/// await showFlagCaptureFlow(context, projectId, ref);
/// ```
Future<void> showFlagCaptureFlow(
  BuildContext context,
  String projectId,
  WidgetRef ref,
) async {
  // D-09: Immediately open the camera — no choice dialog.
  String? photoPath;
  String? annotationJson;

  final picker = ImagePicker();
  final XFile? picked = await picker.pickImage(source: ImageSource.camera);

  if (picked != null) {
    // Push to annotation screen for optional markup
    if (context.mounted) {
      final annotationResult = await Navigator.push<String?>(
        context,
        MaterialPageRoute<String?>(
          builder: (_) => PhotoAnnotationScreen(localPath: picked.path),
        ),
      );
      photoPath = picked.path;
      annotationJson = annotationResult;
    }
  }
  // If picked == null, user cancelled camera → fall through to flag form
  // without a photo (this is the "skip photo" path per D-09).

  if (!context.mounted) return;

  final authState = ref.read(authNotifierProvider);
  final companyId =
      authState is AuthAuthenticated ? authState.companyId : '';
  final userId = authState is AuthAuthenticated ? authState.userId : '';

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _FlagForm(
      projectId: projectId,
      companyId: companyId,
      flaggedBy: userId,
      initialPhotoPath: photoPath,
      initialAnnotationJson: annotationJson,
      ref: ref,
    ),
  );
}

/// Internal flag form rendered in the bottom sheet.
class _FlagForm extends StatefulWidget {
  const _FlagForm({
    required this.projectId,
    required this.companyId,
    required this.flaggedBy,
    required this.ref,
    this.initialPhotoPath,
    this.initialAnnotationJson,
  });

  final String projectId;
  final String companyId;
  final String flaggedBy;
  final WidgetRef ref;
  final String? initialPhotoPath;
  final String? initialAnnotationJson;

  @override
  State<_FlagForm> createState() => _FlagFormState();
}

class _FlagFormState extends State<_FlagForm> {
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  String _severity = 'medium';
  String? _photoPath;
  String? _annotationJson;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _photoPath = widget.initialPhotoPath;
    _annotationJson = widget.initialAnnotationJson;
  }

  @override
  void dispose() {
    _descController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _removePhoto() {
    setState(() {
      _photoPath = null;
      _annotationJson = null;
    });
  }

  Future<void> _submit() async {
    final desc = _descController.text.trim();
    if (desc.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final dao = widget.ref.read(siteWalkFlagDaoProvider);
      await dao.createFlag(SiteWalkFlagsCompanion.insert(
        id: Value(const Uuid().v4()),
        companyId: widget.companyId,
        projectId: widget.projectId,
        flaggedBy: widget.flaggedBy,
        description: desc,
        severity: Value(_severity),
        locationLabel: Value(_locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim()),
        photoUrl: Value(_photoPath),
        annotationData: Value(_annotationJson),
        status: const Value('open'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flag recorded.')),
        );
      }
    } catch (e) {
      debugPrint('[FlagCaptureSheet] Submit error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to save flag. Please try again.')),
        );
        setState(() => _isSubmitting = false);
      }
    }
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
              'Flag Issue',
              style:
                  textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // Photo preview (if any) with remove option
            if (_photoPath != null) ...[
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_photoPath!),
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _removePhoto,
                    child: const Text('Remove photo'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Description
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (required)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Severity
            DropdownButtonFormField<String>(
              initialValue: _severity,
              decoration: const InputDecoration(
                labelText: 'Severity',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (val) =>
                  setState(() => _severity = val ?? 'medium'),
            ),
            const SizedBox(height: 16),

            // Location (optional)
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                hintText: 'e.g. Northeast corner, 2nd floor',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (_descController.text.trim().isNotEmpty && !_isSubmitting)
                        ? _submit
                        : null,
                child: const Text('Submit Flag'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
