import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/companies.dart';
import '../../../shared/models/trade_type.dart';
import '../domain/company_entity.dart';

part 'company_dao.g.dart';

/// Drift DAO for Company CRUD operations.
///
/// All read methods return [Stream] — this is the offline-first pattern.
/// UI widgets watch streams from the local DB; they never await HTTP directly.
/// HTTP sync (Phase 2) writes to the local DB, which automatically notifies
/// all active streams.
@DriftAccessor(tables: [Companies])
class CompanyDao extends DatabaseAccessor<AppDatabase> with _$CompanyDaoMixin {
  CompanyDao(super.db);

  /// Reactive stream of all companies in local DB.
  ///
  /// UI should watch this stream rather than fetching once.
  Stream<List<CompanyEntity>> watchAllCompanies() {
    return (select(companies)).watch().map(
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

  /// Insert a new company. Returns the rowid of the inserted row.
  Future<int> insertCompany(CompaniesCompanion entry) {
    return into(companies).insert(entry);
  }

  /// Update an existing company. Returns true if a row was updated.
  Future<bool> updateCompany(CompaniesCompanion entry) {
    return update(companies).replace(entry);
  }

  /// Delete a company by ID. Returns the number of rows deleted.
  Future<int> deleteCompany(String id) {
    return (delete(companies)..where((tbl) => tbl.id.equals(id))).go();
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
