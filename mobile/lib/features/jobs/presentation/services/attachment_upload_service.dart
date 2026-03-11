import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/dio_client.dart';

/// Upload progress event emitted after each attachment upload completes or fails.
typedef UploadProgressEvent = ({int total, int completed});

/// Handles binary file uploads for pending [Attachment] records.
///
/// Attachments are NOT routed through the sync_queue text outbox — they require
/// multipart/form-data uploads via this dedicated service.
///
/// Text-first sync: [SyncEngine.drainQueue] must complete before [uploadPending]
/// is called, ensuring the note record exists on the server before its
/// attachments are uploaded (referential integrity).
///
/// Upload strategy:
/// - Per attachment: 3 retries with exponential backoff (5s, 15s, 45s)
/// - After 3 failures on one attachment: log and continue to the next
/// - Upload on any connection (WiFi or cellular) per user decision
///
/// Progress is exposed via [progressStream] for sync status indicator:
/// - Emits [UploadProgressEvent] (total, completed) after each upload resolves
/// - [SyncStatusProvider] merges this stream to show "X photos uploading (Y/X)"
class AttachmentUploadService {
  final DioClient _dioClient;
  final AttachmentDao _attachmentDao;

  final _progressController =
      StreamController<UploadProgressEvent>.broadcast();

  AttachmentUploadService({
    required DioClient dioClient,
    required AttachmentDao attachmentDao,
  })  : _dioClient = dioClient,
        _attachmentDao = attachmentDao;

  /// Stream of upload progress events.
  ///
  /// Emits after each individual attachment upload completes or fails.
  /// SyncStatusProvider subscribes to this to display upload progress.
  Stream<UploadProgressEvent> get progressStream => _progressController.stream;

  /// Upload all pending attachments to the backend.
  ///
  /// Fetches attachments with upload_status = 'pending_upload' or 'failed',
  /// then uploads each one in sequence. Emits progress events after each.
  ///
  /// Called by [SyncEngine] after [drainQueue] completes (text-first sync).
  Future<void> uploadPending() async {
    final pending = await _attachmentDao.getPendingUploads();
    if (pending.isEmpty) return;

    final total = pending.length;
    var completed = 0;

    for (final Attachment attachment in pending) {
      final success = await _uploadWithRetry(attachment);
      completed++;
      _progressController.add((total: total, completed: completed));

      if (!success) {
        debugPrint(
          '[AttachmentUploadService] Skipped attachment ${attachment.id} '
          'after max retries',
        );
      }
    }
  }

  /// Upload a single attachment with exponential backoff retry.
  ///
  /// Retry delays: 5s, 15s, 45s (3 attempts total).
  /// Returns true on success, false after exhausting retries.
  Future<bool> _uploadWithRetry(Attachment attachment) async {
    const retryDelays = [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 45),
    ];
    const maxRetries = 3;

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await _attachmentDao.setUploadStatus(attachment.id, 'uploading');
        await _doUpload(attachment);
        return true;
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        final is4xx =
            statusCode != null && statusCode >= 400 && statusCode < 500;

        if (is4xx) {
          // Client error — mark failed, skip (do not retry 4xx)
          debugPrint(
            '[AttachmentUploadService] 4xx error for ${attachment.id}: '
            '$statusCode — skipping',
          );
          await _attachmentDao.incrementRetry(attachment.id);
          return false;
        }

        // Server error or timeout — apply backoff and retry
        final isLastAttempt = attempt == maxRetries - 1;
        if (isLastAttempt) {
          debugPrint(
            '[AttachmentUploadService] Max retries exhausted for '
            '${attachment.id}',
          );
          await _attachmentDao.incrementRetry(attachment.id);
          return false;
        }

        debugPrint(
          '[AttachmentUploadService] Retry ${attempt + 1}/$maxRetries '
          'for ${attachment.id} after ${retryDelays[attempt]}',
        );
        await Future<void>.delayed(retryDelays[attempt]);
      } catch (e) {
        // Unexpected error — log and mark failed
        debugPrint(
          '[AttachmentUploadService] Unexpected error for '
          '${attachment.id}: $e',
        );
        await _attachmentDao.incrementRetry(attachment.id);
        return false;
      }
    }

    return false;
  }

  /// Perform the actual multipart upload for one attachment.
  Future<void> _doUpload(Attachment attachment) async {
    // Verify the local file exists before attempting upload
    final file = File(attachment.localPath);
    if (!file.existsSync()) {
      throw Exception(
        'Local file not found: ${attachment.localPath}',
      );
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        attachment.localPath,
        filename: attachment.localPath.split('/').last,
      ),
      'note_id': attachment.noteId,
      'attachment_type': attachment.attachmentType,
      if (attachment.caption != null) 'caption': attachment.caption!,
    });

    final response = await _dioClient.instance.post<Map<String, dynamic>>(
      '/files/upload',
      data: formData,
      options: Options(
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      ),
    );

    final data = response.data;
    if (data == null) {
      throw Exception('Empty response from upload endpoint');
    }

    final remoteUrl = data['url'] as String?;
    if (remoteUrl == null) {
      throw FormatException(
        'Missing "url" field in upload response',
      );
    }

    await _attachmentDao.markUploaded(attachment.id, remoteUrl);
  }

  /// Close the progress stream.
  ///
  /// Call on app teardown; normally not needed since this is a singleton.
  void dispose() {
    _progressController.close();
  }
}
