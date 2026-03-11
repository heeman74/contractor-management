import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttachmentDao', () {
    test('insertAttachment sets uploadStatus to pending_upload',
        skip: 'Wave 0 stub — implementation in plan 06-02', () {
      // Will test: insertAttachment writes record with uploadStatus = UploadStatus.pendingUpload
    });

    test('getPendingUploads returns pending and failed',
        skip: 'Wave 0 stub — implementation in plan 06-02', () {
      // Will test: getPendingUploads returns attachments with pendingUpload or uploadFailed status
    });

    test('markUploaded sets remoteUrl and status',
        skip: 'Wave 0 stub — implementation in plan 06-06', () {
      // Will test: markUploaded updates remoteUrl and sets uploadStatus to uploaded
    });
  });
}
