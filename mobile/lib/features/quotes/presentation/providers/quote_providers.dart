import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateNotifier / StateNotifierProvider moved to legacy in Riverpod 3.
// ignore: depend_on_referenced_packages
import 'package:riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../domain/line_item_entity.dart';
import '../../domain/quote_entity.dart';

// ─── DAO Providers ────────────────────────────────────────────────────────────

/// Provider exposing the [QuoteDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [QuoteDao] is a database accessor registered
/// at startup in service_locator.dart. (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final quoteDaoProvider = Provider<QuoteDao>((ref) {
  return getIt<QuoteDao>();
});

// ─── Stream Providers ─────────────────────────────────────────────────────────

/// Reactive stream of all non-deleted quotes for a job.
///
/// Returns the list ordered by revisionNumber descending (latest first).
/// Emits an empty list when no quotes exist yet.
final quoteForJobProvider =
    StreamProvider.autoDispose.family<List<QuoteEntity>, String>(
  (ref, jobId) {
    final dao = ref.watch(quoteDaoProvider);
    return dao.watchQuotesForJob(jobId);
  },
);

/// Reactive stream of a single quote by ID.
///
/// Emits null when the quote is not found or soft-deleted.
final quoteByIdProvider =
    StreamProvider.autoDispose.family<QuoteEntity?, String>(
  (ref, quoteId) {
    final dao = ref.watch(quoteDaoProvider);
    return dao.watchQuote(quoteId);
  },
);

/// Reactive stream of all saved quote templates.
///
/// Templates are local-only — they are never synced to the backend.
/// Ordered alphabetically by name.
final quoteTemplatesProvider =
    StreamProvider.autoDispose<List<QuoteTemplate>>((ref) {
  final dao = ref.watch(quoteDaoProvider);
  return dao.watchTemplates();
});

// ─── Quote Builder State ──────────────────────────────────────────────────────

/// In-memory state for the quote being built or edited by the admin.
class QuoteBuilderState {
  final List<LineItemEntity> lineItems;
  final double taxRate;

  /// Discount type: 'none', 'percentage', or 'fixed'.
  final String discountType;
  final double discountValue;
  final DateTime? expiryDate;
  final String adminNotes;

  /// Whether the form has been submitted with invalid data (drives inline errors).
  final bool showValidationErrors;

  const QuoteBuilderState({
    required this.lineItems,
    required this.taxRate,
    required this.discountType,
    required this.discountValue,
    required this.adminNotes,
    this.expiryDate,
    this.showValidationErrors = false,
  });

  factory QuoteBuilderState.empty() => const QuoteBuilderState(
        lineItems: [],
        taxRate: 0.0,
        discountType: 'none',
        discountValue: 0.0,
        adminNotes: '',
      );

  factory QuoteBuilderState.fromEntity(QuoteEntity entity) =>
      QuoteBuilderState(
        lineItems: List.from(entity.lineItems),
        taxRate: entity.taxRate,
        discountType: entity.discountType ?? 'none',
        discountValue: entity.discountValue,
        expiryDate: entity.expiryDate,
        adminNotes: entity.adminNotes ?? '',
      );

  // ─── Computed totals ───────────────────────────────────────────────────────

  double get subtotal =>
      lineItems.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get discountAmount {
    if (discountType == 'percentage') return subtotal * discountValue / 100;
    if (discountType == 'fixed') return discountValue;
    return 0.0;
  }

  double get discountedSubtotal => subtotal - discountAmount;

  double get taxAmount => discountedSubtotal * taxRate / 100;

  double get total => discountedSubtotal + taxAmount;

  // ─── Validation ────────────────────────────────────────────────────────────

  /// Returns a map of field validation errors. Empty = valid.
  Map<String, String> get validationErrors {
    final errors = <String, String>{};
    if (lineItems.isEmpty) {
      errors['lineItems'] = 'Add at least one line item';
    }
    for (var i = 0; i < lineItems.length; i++) {
      final item = lineItems[i];
      if (item.description.trim().isEmpty) {
        errors['lineItem_${item.id}_description'] = 'Description is required';
      }
      if (item.quantity <= 0) {
        errors['lineItem_${item.id}_quantity'] = 'Quantity must be > 0';
      }
      if (item.unitPrice < 0) {
        errors['lineItem_${item.id}_unitPrice'] = 'Price cannot be negative';
      }
    }
    return errors;
  }

  bool get isValid => validationErrors.isEmpty;

  // ─── copyWith ──────────────────────────────────────────────────────────────

  QuoteBuilderState copyWith({
    List<LineItemEntity>? lineItems,
    double? taxRate,
    String? discountType,
    double? discountValue,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    String? adminNotes,
    bool? showValidationErrors,
  }) {
    return QuoteBuilderState(
      lineItems: lineItems ?? this.lineItems,
      taxRate: taxRate ?? this.taxRate,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      adminNotes: adminNotes ?? this.adminNotes,
      showValidationErrors: showValidationErrors ?? this.showValidationErrors,
    );
  }
}

/// StateNotifier managing the in-memory quote being built by the admin.
///
/// Provides methods for all mutations: addLineItem, removeLineItem,
/// updateLineItem, reorderLineItem, setTaxRate, setDiscount, setExpiry,
/// loadFromTemplate, and reset.
///
/// NOTE: This is a sync Notifier with fire-and-forget load methods because
/// the actual DB persistence is triggered by explicit user actions (Save Draft,
/// Preview), not on every field change. Template loading reads synchronous data
/// passed in as arguments — no async needed.
class QuoteBuilderNotifier extends StateNotifier<QuoteBuilderState> {
  QuoteBuilderNotifier() : super(QuoteBuilderState.empty());

  // ─── Line item mutations ────────────────────────────────────────────────────

  void addLineItem() {
    final newItem = LineItemEntity(
      id: const Uuid().v4(),
      itemType: 'labor',
      description: '',
      quantity: 1.0,
      unit: 'each',
      unitPrice: 0.0,
      sortOrder: state.lineItems.length,
    );
    state = state.copyWith(lineItems: [...state.lineItems, newItem]);
  }

  void removeLineItem(String itemId) {
    final updated = state.lineItems
        .where((item) => item.id != itemId)
        .toList();
    // Re-number sortOrders after removal
    final renumbered = [
      for (var i = 0; i < updated.length; i++)
        updated[i].copyWith(sortOrder: i),
    ];
    state = state.copyWith(lineItems: renumbered);
  }

  void updateLineItem(LineItemEntity updatedItem) {
    final updated = state.lineItems.map((item) {
      return item.id == updatedItem.id ? updatedItem : item;
    }).toList();
    state = state.copyWith(lineItems: updated);
  }

  /// Reorder a line item from [oldIndex] to [newIndex] (ReorderableListView indices).
  void reorderLineItem(int oldIndex, int newIndex) {
    // ReorderableListView passes newIndex accounting for the removed item.
    if (newIndex > oldIndex) newIndex--;
    final updated = List<LineItemEntity>.from(state.lineItems);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    // Re-assign sortOrders to match new positions
    final renumbered = [
      for (var i = 0; i < updated.length; i++)
        updated[i].copyWith(sortOrder: i),
    ];
    state = state.copyWith(lineItems: renumbered);
  }

  // ─── Financial field mutations ──────────────────────────────────────────────

  void setTaxRate(double rate) => state = state.copyWith(taxRate: rate);

  void setDiscount({required String type, required double value}) {
    state = state.copyWith(discountType: type, discountValue: value);
  }

  void setExpiry(DateTime? date) {
    if (date == null) {
      state = state.copyWith(clearExpiryDate: true);
    } else {
      state = state.copyWith(expiryDate: date);
    }
  }

  void setAdminNotes(String notes) =>
      state = state.copyWith(adminNotes: notes);

  // ─── Template loading ───────────────────────────────────────────────────────

  /// Pre-fill the builder with line items and tax rate from a saved template.
  ///
  /// Parses the JSON-encoded line items stored in [template.lineItemsJson].
  void loadFromTemplate(QuoteTemplate template) {
    List<LineItemEntity> items = [];
    try {
      final decoded = jsonDecode(template.lineItemsJson) as List<dynamic>;
      items = [
        for (var i = 0; i < decoded.length; i++)
          _parseLineItemFromJson(decoded[i] as Map<String, dynamic>, i),
      ];
    } catch (e) {
      // Template JSON malformed — start with empty list, non-fatal
      debugPrint('QuoteBuilderNotifier: Template parse error: $e');
    }
    state = state.copyWith(
      lineItems: items,
      taxRate: template.taxRate,
    );
  }

  // ─── Validation ────────────────────────────────────────────────────────────

  void triggerValidation() {
    state = state.copyWith(showValidationErrors: true);
  }

  void clearValidation() {
    state = state.copyWith(showValidationErrors: false);
  }

  // ─── Reset ─────────────────────────────────────────────────────────────────

  void reset() => state = QuoteBuilderState.empty();

  /// Load an existing quote into the builder for editing.
  void loadFromEntity(QuoteEntity entity) {
    state = QuoteBuilderState.fromEntity(entity);
  }

  // ─── Private helpers ────────────────────────────────────────────────────────

  LineItemEntity _parseLineItemFromJson(Map<String, dynamic> json, int index) {
    return LineItemEntity(
      id: json['id'] as String? ?? const Uuid().v4(),
      itemType: json['item_type'] as String? ?? 'labor',
      description: json['description'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: json['unit'] as String? ?? 'each',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      sortOrder: json['sort_order'] as int? ?? index,
    );
  }
}

/// Provider for the in-memory quote builder state.
///
/// Scoped to a specific job ID so admin can have separate builder state
/// per job without cross-contamination.
final quoteBuilderNotifierProvider = StateNotifierProvider.autoDispose
    .family<QuoteBuilderNotifier, QuoteBuilderState, String>(
  (ref, jobId) => QuoteBuilderNotifier(),
);
