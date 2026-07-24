import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart'
    show PunchListItem, PunchListItemsCompanion;
import '../providers/project_providers.dart';

/// Bottom sheet showing full punch list item details and status update.
///
/// Contractor can update status (open → in_progress → resolved).
/// GC/admin can additionally set status to 'verified'.
class PunchItemDetailSheet extends StatefulWidget {
  const PunchItemDetailSheet({
    required this.item,
    required this.ref,
    required this.isGcOrAdmin,
    super.key,
  });

  final PunchListItem item;
  final WidgetRef ref;
  final bool isGcOrAdmin;

  @override
  State<PunchItemDetailSheet> createState() => _PunchItemDetailSheetState();
}

class _PunchItemDetailSheetState extends State<PunchItemDetailSheet> {
  late String _selectedStatus;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.item.status;
  }

  List<String> get _allowedStatuses {
    // Contractor: open → in_progress → resolved
    // GC/admin: can also verify
    const base = ['open', 'in_progress', 'resolved'];
    return widget.isGcOrAdmin ? [...base, 'verified'] : base;
  }

  Future<void> _updateStatus(String newStatus) async {
    if (newStatus == widget.item.status) return;
    setState(() => _isUpdating = true);
    try {
      final dao = widget.ref.read(punchListItemDaoProvider);
      await dao.updateItem(
        widget.item.id,
        PunchListItemsCompanion(
          status: Value(newStatus),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Status updated to ${newStatus.replaceAll('_', ' ')}.')),
        );
      }
    } catch (e) {
      debugPrint('[PunchItemDetail] Update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update status.')),
        );
        setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.item.description,
            style:
                textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Text(
            'Priority: ${widget.item.priority}  •  Status: ${widget.item.status.replaceAll('_', ' ')}',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('Update Status', style: textTheme.labelMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedStatus,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _allowedStatuses
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.replaceAll('_', ' ')),
                  ),
                )
                .toList(),
            onChanged: (val) =>
                setState(() => _selectedStatus = val ?? _selectedStatus),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isUpdating
                  ? null
                  : () => _updateStatus(_selectedStatus),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
