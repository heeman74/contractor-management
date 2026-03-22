import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/project_zones.dart';
import '../../../core/database/tables/sync_queue.dart';

part 'project_zone_dao.g.dart';

/// Drift DAO for ProjectZone CRUD and reactive queries.
///
/// ProjectZones are named spatial areas within a project (e.g., Kitchen,
/// Master Bath, Garage). They are used for resource conflict detection —
/// preventing two trades from being scheduled in the same zone simultaneously.
///
/// Zones are synced from the backend and cached locally for offline access.
@DriftAccessor(tables: [ProjectZones, SyncQueue])
class ProjectZoneDao extends DatabaseAccessor<AppDatabase>
    with _$ProjectZoneDaoMixin {
  ProjectZoneDao(super.db);

  /// Watch all non-deleted zones for a given project, ordered by name.
  ///
  /// Emits a new list whenever any zone in the project changes.
  Stream<List<ProjectZone>> watchByProject(String projectId) {
    return (select(projectZones)
          ..where((z) => z.projectId.equals(projectId))
          ..where((z) => z.deletedAt.isNull())
          ..orderBy([(z) => OrderingTerm.asc(z.name)]))
        .watch();
  }

  /// Fetch all non-deleted zones for a given project (one-time read).
  Future<List<ProjectZone>> getByProject(String projectId) {
    return (select(projectZones)
          ..where((z) => z.projectId.equals(projectId))
          ..where((z) => z.deletedAt.isNull())
          ..orderBy([(z) => OrderingTerm.asc(z.name)]))
        .get();
  }

  /// Upsert a zone received from the backend sync pull.
  ///
  /// Uses insert-on-conflict-update for idempotency — safe to call
  /// multiple times with the same data.
  Future<void> upsertZone(ProjectZonesCompanion companion) async {
    await into(projectZones).insertOnConflictUpdate(companion);
  }

  /// Insert a new zone and atomically enqueue a CREATE sync item.
  ///
  /// [companion.id] must already have a value (client-generated UUID).
  Future<void> insertWithSyncQueue(ProjectZonesCompanion companion) async {
    await transaction(() async {
      await into(projectZones).insert(companion);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'project_zone',
          entityId: companion.id.value,
          operation: 'CREATE',
          payload: {
            'id': companion.id.value,
            'project_id': companion.projectId.value,
            'name': companion.name.value,
          },
        ),
      );
    });
  }

  /// Soft-delete a zone and atomically enqueue a DELETE sync item.
  Future<void> softDeleteWithSyncQueue(String id) async {
    await transaction(() async {
      await (update(projectZones)..where((z) => z.id.equals(id)))
          .write(ProjectZonesCompanion(deletedAt: Value(DateTime.now())));
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'project_zone',
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
}
