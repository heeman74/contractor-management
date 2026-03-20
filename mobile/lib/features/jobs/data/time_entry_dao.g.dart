// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'time_entry_dao.dart';

// ignore_for_file: type=lint
mixin _$TimeEntryDaoMixin on DatabaseAccessor<AppDatabase> {
  $TimeEntriesTable get timeEntries => attachedDatabase.timeEntries;
  $SyncQueueTable get syncQueue => attachedDatabase.syncQueue;
  TimeEntryDaoManager get managers => TimeEntryDaoManager(this);
}

class TimeEntryDaoManager {
  final _$TimeEntryDaoMixin _db;
  TimeEntryDaoManager(this._db);
  $$TimeEntriesTableTableManager get timeEntries =>
      $$TimeEntriesTableTableManager(_db.attachedDatabase, _db.timeEntries);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
