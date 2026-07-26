import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/dio_client.dart';

/// Upload progress event emitted after each receipt upload completes or fails.
typedef CostReceiptUploadProgressEvent = ({int total, int completed});

/// Handles binary file uploads for pending [CostReceipt] records.
///
/// Mirrors `AttachmentUploadService` EXACTLY (NOT the broken
/// `TaskAttachment` flow — 31-RESEARCH.md Pitfall 1: `TaskAttachmentDao`'s
/// sync_queue entries have no registered handler and are silently never
/// uploaded). Receipts are NOT routed through the sync_queue text outbox —
/// they require multipart/form-data uploads via this dedicated service.
///
/// Text-first sync: [SyncEngine.drainQueue] (which pushes the cost entry
/// itself via `CostEntrySyncHandler`) must complete before [uploadPending]
/// is called, ensuring the cost entry exists on the server before its
/// receipts are posted — referential integrity, same as `AttachmentUploadService`.
///
/// Upload strategy:
/// - Per receipt: 3 retries with exponential backoff (5s, 15s, 45s)
/// - 4xx = fail-no-retry; 5xx/timeout = backoff + retry
/// - After 3 failures on one receipt: log and continue to the next
class CostReceiptUploadService {
  final DioClient _dioClient;
  final CostReceiptDao _costReceiptDao;

  final _progressController =
      StreamController<CostReceiptUploadProgressEvent>.broadcast();

  CostReceiptUploadService({
    required DioClient dioClient,
    required CostReceiptDao costReceiptDao,
  })  : _dioClient = dioClient,
        _costReceiptDao = costReceiptDao;

  /// Stream of upload progress events.
  Stream<CostReceiptUploadProgressEvent> get progressStream =>
      _progressController.stream;

  /// Upload all pending receipts to the backend.
  ///
  /// Fetches receipts with upload_status = 'pending_upload' or 'failed',
  /// then uploads each one in sequence. Emits progress events after each.
  ///
  /// Called by [SyncEngine] after [drainQueue] completes (text-first sync).
  Future<void> uploadPending() async {
    final pending = await _costReceiptDao.getPendingUploads();
    if (pending.isEmpty) return;

    final total = pending.length;
    var completed = 0;

    for (final CostReceipt receipt in pending) {
      final success = await _uploadWithRetry(receipt);
      completed++;
      _progressController.add((total: total, completed: completed));

      if (!success) {
        debugPrint(
          '[CostReceiptUploadService] Skipped receipt ${receipt.id} '
          'after max retries',
        );
      }
    }
  }

  /// Upload a single receipt with exponential backoff retry.
  ///
  /// Retry delays: 5s, 15s, 45s (3 attempts total).
  /// Returns true on success, false after exhausting retries.
  Future<bool> _uploadWithRetry(CostReceipt receipt) async {
    const retryDelays = [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 45),
    ];
    const maxRetries = 3;

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await _costReceiptDao.setUploadStatus(receipt.id, 'uploading');
        await _doUpload(receipt);
        return true;
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        final is4xx =
            statusCode != null && statusCode >= 400 && statusCode < 500;

        if (is4xx) {
          // Client error — mark failed, skip (do not retry 4xx)
          debugPrint(
            '[CostReceiptUploadService] 4xx error for ${receipt.id}: '
            '$statusCode — skipping',
          );
          await _costReceiptDao.incrementRetry(receipt.id);
          return false;
        }

        // Server error or timeout — apply backoff and retry
        final isLastAttempt = attempt == maxRetries - 1;
        if (isLastAttempt) {
          debugPrint(
            '[CostReceiptUploadService] Max retries exhausted for '
            '${receipt.id}',
          );
          await _costReceiptDao.incrementRetry(receipt.id);
          return false;
        }

        debugPrint(
          '[CostReceiptUploadService] Retry ${attempt + 1}/$maxRetries '
          'for ${receipt.id} after ${retryDelays[attempt]}',
        );
        await Future<void>.delayed(retryDelays[attempt]);
      } catch (e) {
        // Unexpected error — log and mark failed
        debugPrint(
          '[CostReceiptUploadService] Unexpected error for '
          '${receipt.id}: $e',
        );
        await _costReceiptDao.incrementRetry(receipt.id);
        return false;
      }
    }

    return false;
  }

  /// Perform the actual multipart upload for one receipt.
  Future<void> _doUpload(CostReceipt receipt) async {
    // Verify the local file exists before attempting upload
    final file = File(receipt.localPath);
    if (!file.existsSync()) {
      throw Exception('Local file not found: ${receipt.localPath}');
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        receipt.localPath,
        filename: receipt.localPath.split('/').last,
      ),
      if (receipt.caption != null) 'caption': receipt.caption,
    });

    final response = await _dioClient.instance.post<Map<String, dynamic>>(
      '/cost-entries/${receipt.costEntryId}/receipts',
      data: formData,
      options: Options(
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      ),
    );

    final data = response.data;
    if (data == null) {
      throw Exception('Empty response from receipt upload endpoint');
    }

    // The backend returns `remote_url` (not `url`).
    final remoteUrl = data['remote_url'] as String?;
    if (remoteUrl == null) {
      throw const FormatException(
        'Missing "remote_url" field in receipt upload response',
      );
    }

    await _costReceiptDao.markUploaded(receipt.id, remoteUrl);
  }

  /// Close the progress stream.
  ///
  /// Call on app teardown; normally not needed since this is a singleton.
  void dispose() {
    _progressController.close();
  }
}
