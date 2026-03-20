// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attachment_dao.dart';

// ignore_for_file: type=lint
mixin _$AttachmentDaoMixin on DatabaseAccessor<AppDatabase> {
  $AttachmentsTable get attachments => attachedDatabase.attachments;
  AttachmentDaoManager get managers => AttachmentDaoManager(this);
}

class AttachmentDaoManager {
  final _$AttachmentDaoMixin _db;
  AttachmentDaoManager(this._db);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db.attachedDatabase, _db.attachments);
}
