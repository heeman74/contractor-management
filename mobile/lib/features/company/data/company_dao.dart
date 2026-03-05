import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/companies.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../shared/models/trade_type.dart';
import '../domain/company_entity.dart';

part 'company_dao.g.dart';

/// Drift DAO for Company CRUD operations.
///
/// All read methods return [Stream] — this is the offline-first pattern.
/// UI widgets watch streams from the local DB; they never await HTTP directly.
/// HTTP sync (Phase 2) writes to the local DB, which automatically notifies
/// all active streams.
///
/// Every mutating method (insert/update/delete) uses [db.transaction] to
/// atomically write to BOTH the companies table AND sync_queue outbox. If
/// either write fails, both are rolled back — no orphaned queue items, no
/// untracked mutations.
@DriftAccessor(tables: [Companies, SyncQueue])
class CompanyDao extends DatabaseAccessor<AppDatabase>
    with _$CompanyDaoMixin {
  CompanyDao(super.db);

  /// Reactive stream of all active (non-deleted) companies in local DB.
  ///
  /// UI should watch this stream rather than fetching once. Soft-deleted
  /// records (deletedAt != null) are excluded — they are tombstones only.
  Stream<List<CompanyEntity>> watchAllCompanies() {
    return (select(companies)
          ..where((tbl) => tbl.deletedAt.isNull()))
        .watch()
        .map(
          (rows) => rows.map(_rowToEntity).toList(),
        );
  }

  /// Fetch a single company by ID. Returns null if not found.
  Future<CompanyEntity?> getCompanyById(String id) async {
    final row = await (select(companies)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _rowToEntity(row);
  }

  /// Insert a new company and atomically enqueue a CREATE sync item.
  ///
  /// Returns the rowid of the inserted row. Both the entity write and the
  /// sync_queue insert happen in a single transaction — if either fails,
  /// both are rolled back.
  Future<int> insertCompany(CompaniesCompanion entry) {
    return db.transaction(() async {
      final rowId = await into(companies).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'company',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _companyPayload(entry),
        ),
      );
      return rowId;
    });
  }

  /// Update an existing company and atomically enqueue an UPDATE sync item.
  ///
  /// Returns true if a row was updated. Both writes are in a single transaction.
  Future<bool> updateCompany(CompaniesCompanion entry) {
    return db.transaction(() async {
      final updated = await update(companies).replace(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'company',
          entityId: entry.id.value,
          operation: 'UPDATE',
          payload: _companyPayload(entry),
        ),
      );
      return updated;
    });
  }

  /// Soft-delete a company (sets deleted_at) and atomically enqueue a DELETE
  /// sync item.
  ///
  /// Soft delete instead of hard delete enables tombstone propagation across
  /// devices — other devices will see the DELETE operation in sync_queue and
  /// mark their local copy as deleted. Returns the number of rows updated.
  Future<int> deleteCompany(String id) {
    return db.transaction(() async {
      final count = await (update(companies)
            ..where((tbl) => tbl.id.equals(id)))
          .write(CompaniesCompanion(deletedAt: Value(DateTime.now())));
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'company',
          entityId: id,
          operation: 'DELETE',
          payload: {'id': id},
        ),
      );
      return count;
    });
  }

  /// Build a [SyncQueueCompanion] outbox entry for the given mutation.
  SyncQueueCompanion _buildQueueEntry({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    return SyncQueueCompanion.insert(
      id: Value(const Uuid().v4()),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: jsonEncode(payload),
      status: const Value('pending'),
      attemptCount: const Value(0),
      createdAt: DateTime.now(),
    );
  }

  /// Build a JSON-serializable payload map from a [CompaniesCompanion].
  Map<String, dynamic> _companyPayload(CompaniesCompanion entry) {
    return {
      'id': entry.id.value,
      'name': entry.name.value,
      if (entry.address.present) 'address': entry.address.value,
      if (entry.phone.present) 'phone': entry.phone.value,
      if (entry.businessNumber.present)
        'businessNumber': entry.businessNumber.value,
      if (entry.logoUrl.present) 'logoUrl': entry.logoUrl.value,
      if (entry.tradeTypes.present) 'tradeTypes': entry.tradeTypes.value,
      if (entry.version.present) 'version': entry.version.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }

  /// Map a Drift [Company] row to a [CompanyEntity] domain object.
  CompanyEntity _rowToEntity(Company row) {
    return CompanyEntity(
      id: row.id,
      name: row.name,
      address: row.address,
      phone: row.phone,
      tradeTypes: TradeType.fromCommaSeparated(row.tradeTypes),
      logoUrl: row.logoUrl,
      businessNumber: row.businessNumber,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
