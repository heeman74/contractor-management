import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment_entity.freezed.dart';
part 'attachment_entity.g.dart';

/// Freezed domain entity for an Attachment.
///
/// Represents a photo, drawing, or document attached to a [NoteEntity].
/// Created offline; uploaded via AttachmentUploadService (Plan 06-03).
///
/// [uploadStatus] mirrors the Drift table column:
///   - 'pending_upload': waiting to be uploaded
///   - 'uploading': upload in progress
///   - 'uploaded': successfully uploaded, [remoteUrl] is set
///   - 'failed': upload failed, will be retried
@freezed
abstract class AttachmentEntity with _$AttachmentEntity {
  const factory AttachmentEntity({
    required String id,
    required String companyId,
    required String noteId,
    required String attachmentType,
    required String localPath,
    String? thumbnailPath,
    String? caption,
    required String uploadStatus,
    String? remoteUrl,
    required int sortOrder,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _AttachmentEntity;

  factory AttachmentEntity.fromJson(Map<String, dynamic> json) =>
      _$AttachmentEntityFromJson(json);
}
