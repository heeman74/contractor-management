import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../domain/quote_entity.dart';
import '../providers/quote_providers.dart';
import '../widgets/line_item_form.dart';
import '../widgets/quote_summary_card.dart';
/// Admin quote creation and editing screen.
///
/// Features:
///   - Template selector to pre-fill line items
///   - ReorderableListView of line items with Labor/Material toggle, units, prices
///   - Tax rate input, discount toggle, expiry date picker, admin notes
///   - Live QuoteSummaryCard showing totals
///   - "Save Draft" persists to Drift (offline-first)
///   - "Preview" navigates to QuotePreviewScreen
///   - Overflow menu: "Save as Template"
class QuoteBuilderScreen extends ConsumerStatefulWidget {
  final String jobId;

  /// When editing an existing quote, pass the current [QuoteEntity].
  final QuoteEntity? existingQuote;

  /// Optional trade scope ID for per-trade quotes (Phase 25).
  ///
  /// When set, the created [QuoteEntity] will have [jobId] = null and
  /// [tradeScopeId] = this value — creating a trade-scoped quote rather than
  /// a job-level quote.
  final String? tradeScopeId;

  const QuoteBuilderScreen({
    required this.jobId,
    super.key,
    this.existingQuote,
    this.tradeScopeId,
  });

  @override
  ConsumerState<QuoteBuilderScreen> createState() => _QuoteBuilderScreenState();
}

class _QuoteBuilderScreenState extends ConsumerState<QuoteBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taxController = TextEditingController();
  final _discountValueController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // If editing an existing quote, pre-load the builder state.
    if (widget.existingQuote != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(quoteBuilderNotifierProvider(widget.jobId).notifier)
            .loadFromEntity(widget.existingQuote!);
        final q = widget.existingQuote!;
        _taxController.text = q.taxRate == 0 ? '' : q.taxRate.toString();
        _discountValueController.text =
            q.discountValue == 0 ? '' : q.discountValue.toString();
        _notesController.text = q.adminNotes ?? '';
      });
    }
  }

  @override
  void dispose() {
    _taxController.dispose();
    _discountValueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builderState =
        ref.watch(quoteBuilderNotifierProvider(widget.jobId));
    final notifier =
        ref.read(quoteBuilderNotifierProvider(widget.jobId).notifier);
    final templatesAsync = ref.watch(quoteTemplatesProvider);
    final isEditing = widget.existingQuote != null;

    final revisionLabel = isEditing
        ? 'Edit Quote v${widget.existingQuote!.revisionNumber}'
        : 'Create Quote';

    return Scaffold(
      appBar: AppBar(
        title: Text(revisionLabel),
        actions: [
          // Save Draft action
          TextButton.icon(
            onPressed: _isSaving ? null : () => _saveDraft(builderState),
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save Draft'),
          ),
          // Preview action
          IconButton(
            icon: const Icon(Icons.preview_outlined),
            tooltip: 'Preview',
            onPressed: () => _goToPreview(builderState),
          ),
          // Overflow menu: Save as Template
          PopupMenuButton<_OverflowAction>(
            onSelected: (action) {
              if (action == _OverflowAction.saveTemplate) {
                _showSaveTemplateDialog(builderState);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _OverflowAction.saveTemplate,
                child: ListTile(
                  leading: Icon(Icons.bookmark_add_outlined),
                  title: Text('Save as Template'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  // ─── Template selector ────────────────────────────────────
                  _TemplateSelectorRow(
                    jobId: widget.jobId,
                    templatesAsync: templatesAsync,
                    notifier: notifier,
                  ),

                  // ─── Line items (ReorderableListView) ─────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Text(
                      'Line Items',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),

                  if (builderState.showValidationErrors &&
                      builderState.lineItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Text(
                        'Add at least one line item',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),

                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: notifier.reorderLineItem,
                    children: [
                      for (final item in builderState.lineItems)
                        LineItemForm(
                          key: ValueKey(item.id),
                          item: item,
                          showValidation: builderState.showValidationErrors,
                          onChanged: notifier.updateLineItem,
                          onDelete: () => notifier.removeLineItem(item.id),
                        ),
                    ],
                  ),

                  // Add Line Item button
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: OutlinedButton.icon(
                      onPressed: notifier.addLineItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Line Item'),
                    ),
                  ),

                  const Divider(height: 24),

                  // ─── Tax rate ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: TextFormField(
                      controller: _taxController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tax Rate (%)',
                        hintText: 'e.g. 10',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        final rate = double.tryParse(value) ?? 0.0;
                        notifier.setTaxRate(rate);
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ─── Discount ─────────────────────────────────────────────
                  _DiscountRow(
                    discountType: builderState.discountType,
                    discountValue: builderState.discountValue,
                    controller: _discountValueController,
                    onChanged: ({required type, required value}) {
                      notifier.setDiscount(type: type, value: value);
                    },
                  ),

                  const SizedBox(height: 12),

                  // ─── Expiry date ──────────────────────────────────────────
                  _ExpiryDateRow(
                    expiryDate: builderState.expiryDate,
                    onChanged: notifier.setExpiry,
                  ),

                  const SizedBox(height: 12),

                  // ─── Admin notes ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Admin Notes (optional)',
                        hintText: 'Notes visible to admin only...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 3,
                      onChanged: notifier.setAdminNotes,
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ─── Summary card (pinned at bottom) ─────────────────────────────
            QuoteSummaryCard(
              subtotal: builderState.subtotal,
              discountAmount: builderState.discountAmount,
              discountType: builderState.discountType,
              discountValue: builderState.discountValue,
              taxRate: builderState.taxRate,
              taxAmount: builderState.taxAmount,
              total: builderState.total,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _saveDraft(QuoteBuilderState builderState) async {
    final notifier =
        ref.read(quoteBuilderNotifierProvider(widget.jobId).notifier);

    // Trigger validation display even on save (drafts still require valid items)
    notifier.triggerValidation();
    if (!builderState.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix validation errors before saving'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authState = ref.read(authNotifierProvider);
      if (authState is! AuthAuthenticated) return;

      final quoteDao = ref.read(quoteDaoProvider);
      final now = DateTime.now();
      final entity = _buildEntity(builderState, authState.companyId, now);

      if (widget.existingQuote != null) {
        await quoteDao.updateQuote(entity);
      } else {
        await quoteDao.createQuote(entity);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save draft: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _goToPreview(QuoteBuilderState builderState) {
    final notifier =
        ref.read(quoteBuilderNotifierProvider(widget.jobId).notifier);
    notifier.triggerValidation();
    if (!builderState.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fix validation errors before previewing'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    context.push(RouteNames.quotePreviewPath(widget.jobId));
  }

  Future<void> _showSaveTemplateDialog(QuoteBuilderState builderState) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as Template'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Template name',
            hintText: 'e.g. Standard Electrical Install',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.isEmpty) return;

    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthAuthenticated) return;

    final quoteDao = ref.read(quoteDaoProvider);
    final lineItemsJson = jsonEncode(
      builderState.lineItems
          .map(
            (item) => {
              'id': item.id,
              'item_type': item.itemType,
              'description': item.description,
              'quantity': item.quantity,
              'unit': item.unit,
              'unit_price': item.unitPrice,
              'sort_order': item.sortOrder,
            },
          )
          .toList(),
    );

    try {
      await quoteDao.createTemplate(
        companyId: authState.companyId,
        name: name,
        lineItemsJson: lineItemsJson,
        taxRate: builderState.taxRate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template "$name" saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save template: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ─── Entity builder ───────────────────────────────────────────────────────────

  QuoteEntity _buildEntity(
    QuoteBuilderState state,
    String companyId,
    DateTime now,
  ) {
    if (widget.existingQuote != null) {
      final existing = widget.existingQuote!;
      return existing.copyWith(
        status: 'draft',
        lineItems: state.lineItems,
        taxRate: state.taxRate,
        discountType: state.discountType == 'none' ? null : state.discountType,
        discountValue: state.discountValue,
        expiryDate: state.expiryDate,
        adminNotes: state.adminNotes.isEmpty ? null : state.adminNotes,
        updatedAt: now,
      );
    }
    // Trade-scoped quote: jobId is null, tradeScopeId is set.
    // Job-level quote: jobId is set, tradeScopeId is null.
    final isScopeQuote = widget.tradeScopeId != null;
    return QuoteEntity(
      id: const Uuid().v4(),
      companyId: companyId,
      jobId: isScopeQuote ? null : widget.jobId,
      tradeScopeId: isScopeQuote ? widget.tradeScopeId : null,
      status: 'draft',
      revisionNumber: 1,
      taxRate: state.taxRate,
      discountType: state.discountType == 'none' ? null : state.discountType,
      discountValue: state.discountValue,
      expiryDate: state.expiryDate,
      adminNotes: state.adminNotes.isEmpty ? null : state.adminNotes,
      lineItems: state.lineItems,
      createdAt: now,
      updatedAt: now,
    );
  }
}

// ─── Overflow action enum ─────────────────────────────────────────────────────

enum _OverflowAction { saveTemplate }

// ─── Template selector row ────────────────────────────────────────────────────

class _TemplateSelectorRow extends StatelessWidget {
  final String jobId;
  final AsyncValue<List<QuoteTemplate>> templatesAsync;
  final QuoteBuilderNotifier notifier;

  const _TemplateSelectorRow({
    required this.jobId,
    required this.templatesAsync,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: templatesAsync.when(
        data: (templates) {
          if (templates.isEmpty) return const SizedBox.shrink();
          return Row(
            children: [
              const Icon(Icons.bookmark_outlined, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                'Templates:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () =>
                      _showTemplateDialog(context, templates),
                  child: const Text('Load Template'),
                ),
              ),
            ],
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }

  void _showTemplateDialog(
      BuildContext context, List<QuoteTemplate> templates) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose Template'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: templates.length,
            itemBuilder: (_, i) {
              final t = templates[i];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(t.name),
                subtitle: t.description != null ? Text(t.description!) : null,
                onTap: () {
                  notifier.loadFromTemplate(t);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

// ─── Discount row ─────────────────────────────────────────────────────────────

class _DiscountRow extends StatelessWidget {
  final String discountType;
  final double discountValue;
  final TextEditingController controller;
  final void Function({required String type, required double value}) onChanged;

  const _DiscountRow({
    required this.discountType,
    required this.discountValue,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Discount',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'none', label: Text('None')),
              ButtonSegment(value: 'percentage', label: Text('%')),
              ButtonSegment(value: 'fixed', label: Text('\$')),
            ],
            selected: {discountType},
            onSelectionChanged: (selected) {
              onChanged(type: selected.first, value: discountValue);
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (discountType != 'none') ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: discountType == 'percentage'
                    ? 'Discount %'
                    : 'Discount Amount',
                prefixText: discountType == 'fixed' ? '\$' : null,
                suffixText: discountType == 'percentage' ? '%' : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                final v = double.tryParse(value) ?? 0.0;
                onChanged(type: discountType, value: v);
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Expiry date row ──────────────────────────────────────────────────────────

class _ExpiryDateRow extends StatelessWidget {
  final DateTime? expiryDate;
  final ValueChanged<DateTime?> onChanged;

  const _ExpiryDateRow({required this.expiryDate, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              expiryDate == null
                  ? 'Expiry date: Not set'
                  : 'Expires: ${_formatDate(expiryDate!)}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    expiryDate ?? DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now(),
                lastDate:
                    DateTime.now().add(const Duration(days: 365)),
              );
              onChanged(picked);
            },
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(expiryDate == null ? 'Set' : 'Change'),
          ),
          if (expiryDate != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              tooltip: 'Clear expiry date',
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
