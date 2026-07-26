// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cost_receipt_dao.dart';

// ignore_for_file: type=lint
mixin _$CostReceiptDaoMixin on DatabaseAccessor<AppDatabase> {
  $CostReceiptsTable get costReceipts => attachedDatabase.costReceipts;
  CostReceiptDaoManager get managers => CostReceiptDaoManager(this);
}

class CostReceiptDaoManager {
  final _$CostReceiptDaoMixin _db;
  CostReceiptDaoManager(this._db);
  $$CostReceiptsTableTableManager get costReceipts =>
      $$CostReceiptsTableTableManager(_db.attachedDatabase, _db.costReceipts);
}
