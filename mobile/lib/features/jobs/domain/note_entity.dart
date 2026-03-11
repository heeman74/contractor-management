import 'package:freezed_annotation/freezed_annotation.dart';

import 'attachment_entity.dart';

part 'note_entity.freezed.dart';
part 'note_entity.g.dart';

/// Freezed domain entity for a JobNote.
///
/// The canonical representation of a field note in the mobile domain layer.
/// Sourced from the local Drift DB (offline-first) and updated via sync.
///
/// [attachments] is eagerly loaded by [NoteDao] — each note carries its
/// associated [AttachmentEntity] list to avoid N+1 queries in the UI.
@freezed
abstract class NoteEntity with _$NoteEntity {
  const NoteEntity._(); // Allow custom getters on the generated class

  const factory NoteEntity({
    required String id,
    required String companyId,
    required String jobId,
    required String authorId,
    required String body,
    required int version,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    @Default([]) List<AttachmentEntity> attachments,
  }) = _NoteEntity;

  factory NoteEntity.fromJson(Map<String, dynamic> json) =>
      _$NoteEntityFromJson(json);
}
