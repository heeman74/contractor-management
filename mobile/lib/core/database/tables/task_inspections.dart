import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'tasks.dart';

/// Drift table definition for the TaskInspection entity.
///
/// A TaskInspection records a GC's formal approve/reject decision on a
/// [ProjectTask]. Each inspection captures the checklist results, any
/// rejection reason and comment, and an optional rejection photo URL.
///
/// Multiple inspections per task are supported — each represents one
/// inspection cycle (contractor submits → GC reviews → approved or rejected,
/// triggering re-work if rejected).
///
/// Offline-first: inspections are created locally via TaskInspectionDao
/// (with outbox dual-write) and synced to the backend when connectivity
/// is restored.
class TaskInspections extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text().references(Companies, #id)();

  /// FK to ProjectTasks.id — the task being inspected.
  TextColumn get taskId => text().references(ProjectTasks, #id)();

  /// FK to Users.id — the GC who performed this inspection.
  /// Soft FK (no hard reference) to avoid cross-feature coupling.
  TextColumn get inspectorId => text()();

  /// Inspection outcome: 'approved' | 'rejected'
  TextColumn get decision => text()();

  /// JSON array of checklist item results.
  /// Each item: { "itemId": "...", "passed": true/false, "note": "..." }
  TextColumn get checklistResults =>
      text().withDefault(const Constant('[]'))();

  /// Short rejection reason code (e.g., 'poor_quality', 'incomplete_work').
  /// Only populated when decision == 'rejected'.
  TextColumn get rejectionReason => text().nullable()();

  /// Free-text comment from the GC explaining the rejection.
  TextColumn get rejectionComment => text().nullable()();

  /// URL or local path of rejection evidence photo.
  TextColumn get rejectionPhotoUrl => text().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
