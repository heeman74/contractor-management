import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../features/invoices/data/invoice_dao.dart';
import '../../../../features/invoices/domain/invoice_entity.dart';
import '../../../../features/quotes/data/quote_dao.dart';
import '../../../../features/quotes/domain/quote_entity.dart';

// ─── DAO providers ────────────────────────────────────────────────────────────

/// Provider exposing the [QuoteDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [QuoteDao] is a database accessor
/// registered at startup in service_locator.dart.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final quoteDaoForBillingProvider = Provider<QuoteDao>((ref) {
  return getIt<QuoteDao>();
});

/// Provider exposing the [InvoiceDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [InvoiceDao] is a database accessor
/// registered at startup in service_locator.dart.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final invoiceDaoForBillingProvider = Provider<InvoiceDao>((ref) {
  return getIt<InvoiceDao>();
});

// ─── Scope-level stream providers ─────────────────────────────────────────────

/// Reactive stream of all non-deleted quotes for a trade scope.
///
/// Watches [QuoteDao.watchQuotesForScope] — offline-first, Drift-backed.
/// Ordered by revisionNumber descending (latest revision first).
/// Auto-disposed when the scope detail screen is popped.
final scopeQuotesProvider =
    StreamProvider.autoDispose.family<List<QuoteEntity>, String>(
  (ref, scopeId) {
    final dao = ref.watch(quoteDaoForBillingProvider);
    return dao.watchQuotesForScope(scopeId);
  },
);

/// Reactive stream of all non-deleted invoices for a trade scope.
///
/// Watches [InvoiceDao.watchInvoicesForScope] — offline-first, Drift-backed.
/// Ordered by issuedAt descending (most recently issued first).
/// Auto-disposed when the scope detail screen is popped.
final scopeInvoicesProvider =
    StreamProvider.autoDispose.family<List<InvoiceEntity>, String>(
  (ref, scopeId) {
    final dao = ref.watch(invoiceDaoForBillingProvider);
    return dao.watchInvoicesForScope(scopeId);
  },
);

// ─── Project-level aggregation providers ─────────────────────────────────────

/// Fetches the project-level quote aggregation summary from the backend.
///
/// Calls GET /projects/{projectId}/quote-summary and returns the raw JSON map
/// with per-trade breakdown:
///   { "scopes": [{ "trade_name": String, "quote_count": int, "subtotal": double }],
///     "grand_total": double }
///
/// Auto-disposed when the project detail screen is popped.
final projectQuoteSummaryProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, projectId) async {
    final dio = getIt<DioClient>();
    final response = await dio.instance.get<Map<String, dynamic>>(
      '/projects/$projectId/quote-summary',
    );

    final data = response.data;
    if (data == null) {
      throw const FormatException(
        'Empty response from /projects/{id}/quote-summary',
      );
    }
    return data;
  },
);

/// Fetches the project-level invoice aggregation summary from the backend.
///
/// Calls GET /projects/{projectId}/invoice-summary and returns the raw JSON map
/// with per-trade breakdown:
///   { "scopes": [{ "trade_name": String, "billed": double, "paid": double, "outstanding": double }],
///     "grand_total": { "billed": double, "paid": double, "outstanding": double } }
///
/// Auto-disposed when the project detail screen is popped.
final projectInvoiceSummaryProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, projectId) async {
    final dio = getIt<DioClient>();
    final response = await dio.instance.get<Map<String, dynamic>>(
      '/projects/$projectId/invoice-summary',
    );

    final data = response.data;
    if (data == null) {
      throw const FormatException(
        'Empty response from /projects/{id}/invoice-summary',
      );
    }
    return data;
  },
);
