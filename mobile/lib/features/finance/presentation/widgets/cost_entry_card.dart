import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart'
    show CostEntry, CostReceipt;
import '../../../../core/network/media_url.dart';
import '../providers/cost_providers.dart';

/// A single cost-entry row: category, amount, date, vendor, receipt
/// thumbnails, and (finance.manage only) a delete action.
///
/// Amount display always uses [toStringAsFixed(2)] — this is a display
/// estimate only; the authoritative rollup total comes from the backend
/// (31-RESEARCH.md Pitfall 5).
class CostEntryCard extends ConsumerWidget {
  const CostEntryCard({required this.entry, super.key});

  final CostEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryNames = ref.watch(costCategoryNameMapProvider);
    final categoryName = categoryNames[entry.categoryId] ?? 'Uncategorized';
    final receiptsAsync = ref.watch(receiptsForCostEntryProvider(entry.id));
    final canManage = ref.watch(financePermissionProvider).canManage;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryName,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        entry.incurredDate,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      if (entry.vendor != null && entry.vendor!.isNotEmpty)
                        Text(
                          entry.vendor!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Text(
                  r'$' '${entry.amount.toStringAsFixed(2)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (canManage)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Delete cost entry',
                    onPressed: () => _confirmDelete(context, ref),
                  ),
              ],
            ),
            if (entry.note != null && entry.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(entry.note!, style: Theme.of(context).textTheme.bodySmall),
            ],
            receiptsAsync.maybeWhen(
              data: (receipts) => receipts.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        height: 56,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: receipts.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (context, index) =>
                              _ReceiptThumbnail(receipt: receipts[index]),
                        ),
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete cost entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(costEntryDaoProvider).softDeleteCostEntry(entry.id);
    }
  }
}

/// Receipt thumbnail: local file until uploaded, then the authenticated
/// remote URL — mirrors [TaskPhotoGrid]'s thumbnail resolution.
class _ReceiptThumbnail extends StatelessWidget {
  const _ReceiptThumbnail({required this.receipt});

  final CostReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: _buildThumbnail(),
    );
  }

  Widget _buildThumbnail() {
    final localPath = receipt.localPath;
    if (localPath.isNotEmpty && File(localPath).existsSync()) {
      return Image.file(
        File(localPath),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, _) => _errorPlaceholder(),
      );
    }
    final remoteUrl = receipt.remoteUrl;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return Image.network(
        resolveMediaUrl(remoteUrl)!,
        headers: mediaAuthHeaders(),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, _) => _errorPlaceholder(),
      );
    }
    return _errorPlaceholder();
  }

  Widget _errorPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: Colors.grey[200],
      child: const Icon(Icons.receipt_long, color: Colors.grey, size: 20),
    );
  }
}
