import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Drift table definition for the DailyChecklist entity.
///
/// A DailyChecklist is an AI-generated morning task checklist for a contractor.
/// It contains the full JSON from the AI (tasks with materials, priorities,
/// photo requirements, and time estimates) and a summary text used for FCM push.
///
/// [contractorId] and [tradeScopeId] are soft FKs — no hard references to
/// keep table definitions decoupled across features.
///
/// Offline-first: checklists are pulled from the backend via sync/delta pull
/// and stored locally. Contractors can view their daily tasks even when offline.
class DailyChecklists extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// FK to Companies.id — tenant scope.
  TextColumn get companyId => text()();

  /// Soft FK to Users.id — the contractor this checklist belongs to.
  TextColumn get contractorId => text()();

  /// Soft FK to Projects.id — the project associated with this checklist.
  TextColumn get projectId => text()();

  /// Soft FK to TradeScopes.id — the trade scope this checklist is for.
  TextColumn get tradeScopeId => text()();

  /// ISO date string (YYYY-MM-DD) — the date this checklist is for.
  TextColumn get checklistDate => text()();

  /// Full AI-generated checklist JSON.
  /// Contains task objects with: task_id, title, priority, estimated_duration,
  /// materials_needed (list), photo_required (bool), dependency_status (string).
  TextColumn get checklistJson => text()();

  /// Short summary text for the FCM push notification body.
  TextColumn get summaryText => text()();

  /// Whether the FCM push notification has been sent for this checklist.
  BoolColumn get isPushed => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// ISO date string for soft-delete tombstone propagation.
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
