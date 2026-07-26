// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cost_entry_dao.dart';

// ignore_for_file: type=lint
mixin _$CostEntryDaoMixin on DatabaseAccessor<AppDatabase> {
  $CompaniesTable get companies => attachedDatabase.companies;
  $CostEntriesTable get costEntries => attachedDatabase.costEntries;
  $ProjectsTable get projects => attachedDatabase.projects;
  $TradeScopesTable get tradeScopes => attachedDatabase.tradeScopes;
  $SyncQueueTable get syncQueue => attachedDatabase.syncQueue;
  CostEntryDaoManager get managers => CostEntryDaoManager(this);
}

class CostEntryDaoManager {
  final _$CostEntryDaoMixin _db;
  CostEntryDaoManager(this._db);
  $$CompaniesTableTableManager get companies =>
      $$CompaniesTableTableManager(_db.attachedDatabase, _db.companies);
  $$CostEntriesTableTableManager get costEntries =>
      $$CostEntriesTableTableManager(_db.attachedDatabase, _db.costEntries);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db.attachedDatabase, _db.projects);
  $$TradeScopesTableTableManager get tradeScopes =>
      $$TradeScopesTableTableManager(_db.attachedDatabase, _db.tradeScopes);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
