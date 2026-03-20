// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_dao.dart';

// ignore_for_file: type=lint
mixin _$NoteDaoMixin on DatabaseAccessor<AppDatabase> {
  $JobNotesTable get jobNotes => attachedDatabase.jobNotes;
  $AttachmentsTable get attachments => attachedDatabase.attachments;
  $SyncQueueTable get syncQueue => attachedDatabase.syncQueue;
  NoteDaoManager get managers => NoteDaoManager(this);
}

class NoteDaoManager {
  final _$NoteDaoMixin _db;
  NoteDaoManager(this._db);
  $$JobNotesTableTableManager get jobNotes =>
      $$JobNotesTableTableManager(_db.attachedDatabase, _db.jobNotes);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db.attachedDatabase, _db.attachments);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
