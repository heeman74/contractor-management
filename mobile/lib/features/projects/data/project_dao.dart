import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/projects.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../../../core/database/tables/trade_scopes.dart';

part 'project_dao.g.dart';

/// Drift DAO for Project CRUD operations.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// [watchProjectsByCompany] is for GC/admin users who can see all projects.
/// [watchProjectsForContractor] is for contractor users — returns only projects
/// where they have an assigned trade scope, enforcing role-based data access.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the entity table AND sync_queue outbox. If either write fails, both are
/// rolled back — no orphaned queue items, no untracked mutations.
@DriftAccessor(tables: [Projects, TradeScopes, SyncQueue])
class ProjectDao extends DatabaseAccessor<AppDatabase> with _$ProjectDaoMixin {
  ProjectDao(super.db);

  /// Reactive stream of all active (non-deleted) projects for a company.
  ///
  /// For GC/admin use. Mirrors backend RLS tenant scope.
  /// Ordered newest first for default list view.
  Stream<List<Project>> watchProjectsByCompany(String companyId) {
    return (select(projects)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();
  }

  /// Reactive stream of projects where the contractor has an assigned trade scope.
  ///
  /// This is the contractor-role-specific query that enforces visibility rules:
  /// contractors can only see projects where they have a [TradeScope] assigned
  /// to them (contractorId matches their userId).
  ///
  /// Uses a two-step approach: first finds distinct project IDs from TradeScopes
  /// where the contractor is assigned, then watches those projects.
  ///
  /// The reactive stream uses [watchProjectsByCompany] and filters in-memory by
  /// the set of project IDs from the contractor's assigned scopes. This avoids
  /// the Drift selectOnly/join complexity while remaining reactive to DB changes.
  Stream<List<Project>> watchProjectsForContractor(
      String companyId, String userId) {
    // Stream of scope projectIds assigned to this contractor
    final scopeProjectIdsStream = (select(tradeScopes)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) &
                tbl.contractorId.equals(userId) &
                tbl.deletedAt.isNull(),
          ))
        .watch()
        .map((scopes) => scopes.map((s) => s.projectId).toSet());

    // Stream of all company projects
    final allProjectsStream = (select(projects)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();

    // Combine: return only projects that appear in contractor's scope set
    return allProjectsStream.asyncExpand((allProjects) =>
        scopeProjectIdsStream.map((projectIds) => allProjects
            .where((p) => projectIds.contains(p.id))
            .toList()));
  }

  /// Fetch a single project by ID. Returns null if not found.
  Future<Project?> getProjectById(String id) async {
    return (select(projects)..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
  }

  /// Insert a new project and atomically enqueue a CREATE sync item.
  ///
  /// Both writes are in a single transaction — no orphaned queue items.
  Future<void> insertProject(ProjectsCompanion entry) async {
    await db.transaction(() async {
      await into(projects).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'project',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _projectPayload(entry),
        ),
      );
    });
  }

  /// Update an existing project and atomically enqueue an UPDATE sync item.
  Future<void> updateProject(String id, ProjectsCompanion entry) async {
    await db.transaction(() async {
      await (update(projects)..where((tbl) => tbl.id.equals(id))).write(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'project',
          entityId: id,
          operation: 'UPDATE',
          payload: _projectPayload(entry),
        ),
      );
    });
  }

  /// Soft-delete a project and atomically enqueue a DELETE sync item.
  ///
  /// Sets [deletedAt] to the current time — the record is not physically removed.
  Future<void> softDeleteProject(String id) async {
    await db.transaction(() async {
      await (update(projects)..where((tbl) => tbl.id.equals(id))).write(
        ProjectsCompanion(deletedAt: Value(DateTime.now())),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'project',
          entityId: id,
          operation: 'DELETE',
          payload: {'id': id},
        ),
      );
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

  /// Build a JSON-serializable payload map from a [ProjectsCompanion].
  Map<String, dynamic> _projectPayload(ProjectsCompanion entry) {
    return {
      if (entry.id.present) 'id': entry.id.value,
      if (entry.companyId.present) 'companyId': entry.companyId.value,
      if (entry.name.present) 'name': entry.name.value,
      if (entry.description.present) 'description': entry.description.value,
      if (entry.address.present) 'address': entry.address.value,
      if (entry.clientId.present) 'clientId': entry.clientId.value,
      if (entry.status.present) 'status': entry.status.value,
      if (entry.statusHistory.present)
        'statusHistory': entry.statusHistory.value,
      if (entry.targetStartDate.present)
        'targetStartDate': entry.targetStartDate.value?.toIso8601String(),
      if (entry.targetEndDate.present)
        'targetEndDate': entry.targetEndDate.value?.toIso8601String(),
      if (entry.version.present) 'version': entry.version.value,
      if (entry.createdAt.present)
        'createdAt': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updatedAt': entry.updatedAt.value.toIso8601String(),
    };
  }
}
