import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../auth/domain/auth_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/line_item_entity.dart';
import '../../domain/quote_entity.dart';
import '../providers/quote_providers.dart';

/// Mutable line item for the change-order form (converted to [LineItemEntity]
/// on save).
class _CoLine {
  _CoLine();
  String itemType = 'labor';
  String description = '';
  double quantity = 1;
  String unit = 'hr';
  double unitPrice = 0;

  double get total => quantity * unitPrice;
}

/// Contractor screen to raise a change order against an existing project from an
/// in-progress job. Persists offline via [QuoteDao.createQuote] (quote_kind =
/// 'change_order'); the sync layer creates it on the backend.
class ChangeOrderBuilderScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String originatingJobId;

  const ChangeOrderBuilderScreen({
    required this.projectId,
    required this.originatingJobId,
    super.key,
  });

  @override
  ConsumerState<ChangeOrderBuilderScreen> createState() =>
      _ChangeOrderBuilderScreenState();
}

class _ChangeOrderBuilderScreenState
    extends ConsumerState<ChangeOrderBuilderScreen> {
  final _reasonController = TextEditingController();
  final _daysController = TextEditingController();
  String _coTarget = 'new_job';
  final List<_CoLine> _lines = [_CoLine()];
  bool _isSaving = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  double get _total => _lines.fold(0.0, (sum, line) => sum + line.total);

  Future<void> _save() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      _showError('Describe the reason for this change order.');
      return;
    }
    final lines = _lines.where((l) => l.description.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      _showError('Add at least one line item with a description.');
      return;
    }
    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthAuthenticated) return;

    setState(() => _isSaving = true);
    try {
      final quoteDao = ref.read(quoteDaoProvider);
      final now = DateTime.now();
      final days = int.tryParse(_daysController.text.trim());

      final entity = QuoteEntity(
        id: const Uuid().v4(),
        companyId: authState.companyId,
        status: 'draft',
        revisionNumber: 1,
        taxRate: 0,
        discountValue: 0,
        quoteKind: 'change_order',
        projectId: widget.projectId,
        originatingJobId: widget.originatingJobId,
        coTarget: _coTarget,
        changeReason: reason,
        scheduleImpactDays: (days != null && days > 0) ? days : null,
        lineItems: [
          for (var i = 0; i < lines.length; i++)
            LineItemEntity(
              id: const Uuid().v4(),
              itemType: lines[i].itemType,
              description: lines[i].description.trim(),
              quantity: lines[i].quantity,
              unit: lines[i].unit.trim().isEmpty ? 'ea' : lines[i].unit.trim(),
              unitPrice: lines[i].unitPrice,
              sortOrder: i,
            ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await quoteDao.createQuote(entity);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Change order saved as draft')),
      );
      context.pop();
    } catch (e) {
      if (mounted) _showError('Failed to save change order: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Change Order'),
        actions: [
          IconButton(
            key: const Key('save_change_order'),
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('co_reason'),
            controller: _reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason for change',
              hintText: 'e.g. Rotted subfloor discovered under the tile',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const Key('co_target'),
            initialValue: _coTarget,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Apply approved work to',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'new_job', child: Text('A new job in the project')),
              DropdownMenuItem(value: 'existing_job', child: Text('This job (extend it)')),
            ],
            onChanged: (v) => setState(() => _coTarget = v ?? 'new_job'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('co_days'),
            controller: _daysController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Schedule impact (days)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Line items', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (var i = 0; i < _lines.length; i++) _lineItemRow(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('add_co_line'),
              onPressed: () => setState(() => _lines.add(_CoLine())),
              icon: const Icon(Icons.add),
              label: const Text('Add line item'),
            ),
          ),
          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total: \$${_total.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineItemRow(int index) {
    final line = _lines[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  initialValue: line.itemType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'labor', child: Text('Labor')),
                    DropdownMenuItem(value: 'material', child: Text('Material')),
                  ],
                  onChanged: (v) => setState(() => line.itemType = v ?? 'labor'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: Key('co_line_desc_$index'),
                  initialValue: line.description,
                  decoration: const InputDecoration(labelText: 'Description', isDense: true),
                  onChanged: (v) => line.description = v,
                ),
              ),
              if (_lines.length > 1)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _lines.removeAt(index)),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: line.quantity.toString(),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                  onChanged: (v) => line.quantity = double.tryParse(v) ?? 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: line.unit,
                  decoration: const InputDecoration(labelText: 'Unit', isDense: true),
                  onChanged: (v) => line.unit = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: Key('co_line_price_$index'),
                  initialValue: line.unitPrice.toString(),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Unit price', isDense: true),
                  onChanged: (v) => setState(() => line.unitPrice = double.tryParse(v) ?? 0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
