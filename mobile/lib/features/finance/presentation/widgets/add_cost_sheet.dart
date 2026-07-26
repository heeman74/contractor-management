import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../jobs/presentation/widgets/add_note_bottom_sheet.dart'
    show compressPhoto;
import '../providers/cost_providers.dart';

/// Modal bottom sheet for adding an offline cost entry with optional
/// camera/gallery receipt capture.
///
/// Takes an anchor (exactly one of [jobId]/[tradeScopeId] — XOR, mirrors
/// [CostEntryDao.insertCostEntry]). On save:
/// 1. [CostEntryDao.insertCostEntry] creates the entry and enqueues a sync
///    item — works fully offline.
/// 2. [CostReceiptDao.insertReceipt] creates each captured receipt with
///    `uploadStatus = 'pending_upload'` — the [CostReceiptUploadService]
///    drains these on the next sync.
///
/// Usage:
/// ```dart
/// AddCostSheet.show(context, jobId: job.id);
/// AddCostSheet.show(context, tradeScopeId: scope.id);
/// ```
class AddCostSheet extends ConsumerStatefulWidget {
  const AddCostSheet._({this.jobId, this.tradeScopeId})
      : assert(
          (jobId == null) != (tradeScopeId == null),
          'AddCostSheet requires exactly one of jobId/tradeScopeId',
        );

  final String? jobId;
  final String? tradeScopeId;

  /// Shows the add-cost bottom sheet. Provide exactly one of [jobId] /
  /// [tradeScopeId].
  static Future<void> show(
    BuildContext context, {
    String? jobId,
    String? tradeScopeId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AddCostSheet._(jobId: jobId, tradeScopeId: tradeScopeId),
    );
  }

  @override
  ConsumerState<AddCostSheet> createState() => _AddCostSheetState();
}

/// A receipt image captured (but not yet saved) in this sheet.
class _PendingReceipt {
  _PendingReceipt({required this.localPath, this.thumbnailPath});

  final String localPath;
  final String? thumbnailPath;
}

class _AddCostSheetState extends ConsumerState<AddCostSheet> {
  final _amountController = TextEditingController();
  final _vendorController = TextEditingController();
  final _noteController = TextEditingController();
  final _imagePicker = ImagePicker();

  String? _categoryId;
  DateTime _incurredDate = DateTime.now();
  final List<_PendingReceipt> _receipts = [];
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _vendorController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? get _parsedAmount => double.tryParse(_amountController.text.trim());

  bool get _canSave =>
      !_isSaving &&
      _categoryId != null &&
      (_parsedAmount ?? 0) > 0 &&
      _amountController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(costCategoriesProvider);

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
              'Add Cost',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // Amount
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (required)',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Category
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(
                'Failed to load categories: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              data: (categories) => DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Category (required)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: categories
                    .map((category) => DropdownMenuItem<String>(
                          value: category['id'] as String?,
                          child: Text(category['name'] as String? ?? ''),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _categoryId = value),
              ),
            ),
            const SizedBox(height: 16),

            // Incurred date
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date incurred',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: Text(_formatDate(_incurredDate)),
              ),
            ),
            const SizedBox(height: 16),

            // Vendor
            TextField(
              controller: _vendorController,
              decoration: const InputDecoration(
                labelText: 'Vendor (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),

            // Note
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            // Receipt capture — camera AND gallery
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Camera'),
                    onPressed: _pickFromCamera,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                    onPressed: _pickFromGallery,
                  ),
                ),
              ],
            ),

            if (_receipts.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _receipts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => _ReceiptThumbnail(
                    receipt: _receipts[index],
                    onRemove: () =>
                        setState(() => _receipts.removeAt(index)),
                  ),
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _save : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Cost'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _incurredDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _incurredDate = picked);
  }

  Future<void> _pickFromCamera() async {
    final xFile = await _imagePicker.pickImage(source: ImageSource.camera);
    if (xFile == null) return;
    await _addReceipt(xFile.path);
  }

  Future<void> _pickFromGallery() async {
    final xFile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    await _addReceipt(xFile.path);
  }

  Future<void> _addReceipt(String sourcePath) async {
    try {
      final (compressedPath, thumbnailPath) = await compressPhoto(sourcePath);
      setState(() => _receipts.add(_PendingReceipt(
            localPath: compressedPath,
            thumbnailPath: thumbnailPath,
          )));
    } catch (e) {
      debugPrint('[AddCostSheet] Receipt capture failed: $e');
      if (mounted) {
        setState(() => _errorMessage = 'Failed to capture receipt: $e');
      }
    }
  }

  Future<void> _save() async {
    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthAuthenticated) {
      setState(() => _errorMessage = 'You must be signed in to add a cost.');
      return;
    }

    final amount = _parsedAmount;
    final categoryId = _categoryId;
    if (amount == null || amount <= 0 || categoryId == null) {
      setState(() => _errorMessage = 'Enter an amount and select a category.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final costEntryDao = ref.read(costEntryDaoProvider);
      final costReceiptDao = ref.read(costReceiptDaoProvider);

      final entryId = await costEntryDao.insertCostEntry(
        companyId: authState.companyId,
        categoryId: categoryId,
        amount: amount,
        incurredDate: _formatIsoDate(_incurredDate),
        jobId: widget.jobId,
        tradeScopeId: widget.tradeScopeId,
        vendor: _vendorController.text.trim().isEmpty
            ? null
            : _vendorController.text.trim(),
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      for (final receipt in _receipts) {
        await costReceiptDao.insertReceipt(
          companyId: authState.companyId,
          costEntryId: entryId,
          localPath: receipt.localPath,
          thumbnailPath: receipt.thumbnailPath,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cost saved — syncs on next connection'),
          ),
        );
      }
    } catch (e) {
      debugPrint('[AddCostSheet] Save failed: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save cost: $e';
        });
      }
    }
  }

  static String _formatIsoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _formatDate(DateTime date) =>
      '${date.month}/${date.day}/${date.year}';
}

class _ReceiptThumbnail extends StatelessWidget {
  const _ReceiptThumbnail({required this.receipt, required this.onRemove});

  final _PendingReceipt receipt;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(receipt.thumbnailPath ?? receipt.localPath),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: GestureDetector(
            onTap: onRemove,
            child: CircleAvatar(
              radius: 10,
              backgroundColor: Theme.of(context).colorScheme.error,
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
