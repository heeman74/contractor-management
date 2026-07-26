import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';

/// Drift table definition for the CostEntry entity.
///
/// A CostEntry records an actual materials/subcontractor/other cost incurred
/// against a job XOR a trade scope (never both — mirrors the backend's XOR
/// anchor validator in `CostEntryCreate`). Money is stored as a [RealColumn]
/// (double) — SQLite has no native Decimal type, matching the existing
/// quotes/invoices money-column convention (31-RESEARCH.md Pitfall 5). Any
/// locally-summed rollup total is a display estimate only; the authoritative
/// total always comes from the backend's `Numeric(10,2)` aggregate query.
///
/// [incurredDate] is stored as an ISO date string (YYYY-MM-DD), matching the
/// `DailyChecklists.checklistDate` TEXT-not-DateTimeColumn precedent.
///
/// Offline-first: cost entries are created locally via [CostEntryDao] (with
/// outbox dual-write) and pushed to the backend via `CostEntrySyncHandler`
/// when connectivity is restored. Inbound reads are ON-DEMAND per
/// job/trade-scope/project (never via the company-wide /sync delta) so
/// non-finance devices never pull cost data (31-RESEARCH.md Pitfall 2).
class CostEntries extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();

  /// Soft FK to Jobs.id — set when the entry is anchored to a job. Exactly
  /// one of [jobId]/[tradeScopeId] is set (XOR anchor), enforced by
  /// [CostEntryDao.insertCostEntry].
  TextColumn get jobId => text().nullable()();

  /// Soft FK to TradeScopes.id — set when the entry is anchored to a trade
  /// scope.
  TextColumn get tradeScopeId => text().nullable()();

  /// Soft FK to CostCategories.id — materials/subcontractor/other/labor.
  TextColumn get categoryId => text()();

  /// Cost amount. Stored as double — see class-level Pitfall 5 note.
  RealColumn get amount => real()();

  /// ISO date string (YYYY-MM-DD) — the date the cost was incurred.
  TextColumn get incurredDate => text()();

  TextColumn get vendor => text().nullable()();
  TextColumn get note => text().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
