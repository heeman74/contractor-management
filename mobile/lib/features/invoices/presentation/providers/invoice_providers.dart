import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/invoice_dao.dart';
import '../../domain/invoice_entity.dart';

// ─── DAO provider ─────────────────────────────────────────────────────────────

/// Provider exposing the [InvoiceDao] singleton from GetIt.
///
/// NOTE: GetIt is used here because [InvoiceDao] is a database accessor
/// registered at startup in service_locator.dart. Riverpod providers that
/// need the DAO read it via this provider. (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final invoiceDaoProvider = Provider<InvoiceDao>((ref) {
  return getIt<InvoiceDao>();
});

// ─── Stream providers ─────────────────────────────────────────────────────────

/// Reactive stream of all invoices for a given job.
///
/// Uses [InvoiceDao.watchInvoicesForJob] — offline-first, Drift-backed.
/// Automatically disposed when no longer watched (autoDispose).
final invoicesForJobProvider =
    StreamProvider.autoDispose.family<List<InvoiceEntity>, String>(
  (ref, jobId) {
    final dao = ref.watch(invoiceDaoProvider);
    return dao.watchInvoicesForJob(jobId);
  },
);

/// Reactive stream of a single invoice by ID with populated line items.
///
/// Emits null if the invoice is not found or has been soft-deleted.
final invoiceDetailProvider =
    StreamProvider.autoDispose.family<InvoiceEntity?, String>(
  (ref, invoiceId) {
    final dao = ref.watch(invoiceDaoProvider);
    return dao.watchInvoice(invoiceId);
  },
);

// ─── API action providers ─────────────────────────────────────────────────────

/// Generates an invoice from an approved quote via POST /invoices/generate/{jobId}.
///
/// Returns the new invoice ID on success. Throws [Exception] on failure.
///
/// Usage: call ref.read(generateInvoiceProvider(jobId).future) to trigger.
final generateInvoiceProvider =
    FutureProvider.autoDispose.family<String, String>((ref, jobId) async {
  final dio = getIt<DioClient>();
  final response = await dio.instance.post<Map<String, dynamic>>(
    '/invoices/generate/$jobId',
  );

  final data = response.data;
  if (data == null || data['id'] is! String) {
    throw FormatException(
      'Invalid response from /invoices/generate/$jobId: expected id field',
    );
  }

  return data['id'] as String;
});

/// Updates the payment status of an invoice via PATCH /invoices/{id}/payment.
///
/// This is an on-demand call — not a provider you watch, but one you call.
/// Status should be one of: 'unpaid', 'partial', 'paid', 'overdue', 'cancelled'.
Future<void> updateInvoicePaymentStatus({
  required String invoiceId,
  required String status,
}) async {
  final dio = getIt<DioClient>();
  await dio.instance.patch<void>(
    '/invoices/$invoiceId/payment',
    data: {'status': status},
  );
}

/// Downloads invoice PDF bytes from GET /invoices/{id}/pdf.
///
/// Returns raw bytes that can be saved to a file or displayed in-app.
Future<List<int>> downloadInvoicePdf(String invoiceId) async {
  final dio = getIt<DioClient>();
  final response = await dio.instance.get<List<int>>(
    '/invoices/$invoiceId/pdf',
    options: Options(responseType: ResponseType.bytes),
  );

  final data = response.data;
  if (data == null) {
    throw const FormatException('No PDF bytes received from server');
  }

  return data;
}

/// Finalizes an invoice via POST /invoices/{id}/finalize.
///
/// After finalization, the invoice cannot be edited.
Future<void> finalizeInvoice(String invoiceId) async {
  final dio = getIt<DioClient>();
  await dio.instance.post<void>('/invoices/$invoiceId/finalize');
}
