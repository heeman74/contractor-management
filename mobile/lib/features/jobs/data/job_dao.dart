import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/client_profiles.dart';
import '../../../core/database/tables/client_properties.dart';
import '../../../core/database/tables/job_requests.dart';
import '../../../core/database/tables/jobs.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../domain/client_profile_entity.dart';
import '../domain/job_entity.dart';
import '../domain/job_request_entity.dart';

part 'job_dao.g.dart';

/// Drift DAO for Job, ClientProfile, ClientProperty, and JobRequest CRUD.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the entity table AND sync_queue outbox. If either write fails, both are
/// rolled back — no orphaned queue items, no untracked mutations.
///
/// Payload serialization: manually build Map<String, dynamic> from Companion
/// fields — [toColumns()] returns Map<String, Expression> which cannot be
/// JSON-encoded (Phase 2 decision).
@DriftAccessor(
  tables: [Jobs, ClientProfiles, ClientProperties, JobRequests, SyncQueue],
)
class JobDao extends DatabaseAccessor<AppDatabase> with _$JobDaoMixin {
  JobDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Job streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of all active (non-deleted) jobs for a company.
  ///
  /// Mirrors backend RLS tenant scope. Ordered newest first for default list view.
  Stream<List<JobEntity>> watchJobsByCompany(String companyId) {
    return (select(jobs)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch()
        .map((rows) => rows.map(_rowToJobEntity).toList());
  }

  /// Reactive stream of active jobs assigned to a specific contractor.
  ///
  /// Used in the contractor's own job list view.
  Stream<List<JobEntity>> watchJobsByContractor(String contractorId) {
    return (select(jobs)
          ..where(
            (tbl) =>
                tbl.contractorId.equals(contractorId) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch()
        .map((rows) => rows.map(_rowToJobEntity).toList());
  }

  /// Reactive stream of active jobs linked to a specific client.
  ///
  /// Used in the CRM client detail screen to show job history.
  Stream<List<JobEntity>> watchJobsByClient(String clientId) {
    return (select(jobs)
          ..where(
            (tbl) =>
                tbl.clientId.equals(clientId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch()
        .map((rows) => rows.map(_rowToJobEntity).toList());
  }

  // ────────────────────────────────────────────────────────────────────────
  // Job mutations (transactional outbox pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new job and atomically enqueue a CREATE sync item.
  ///
  /// Both the entity write and sync_queue insert happen in a single
  /// transaction — if either fails, both are rolled back.
  Future<void> insertJob(JobsCompanion entry) async {
    await db.transaction(() async {
      await into(jobs).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'job',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _jobPayload(entry),
        ),
      );
    });
  }

  /// Update a job's status and atomically enqueue an UPDATE sync item.
  ///
  /// The sync payload includes the new status and current version for
  /// optimistic locking on the backend.
  Future<void> updateJobStatus(
    String jobId,
    String newStatus,
    String statusHistoryJson,
    int newVersion,
  ) async {
    await db.transaction(() async {
      await (update(jobs)..where((tbl) => tbl.id.equals(jobId))).write(
        JobsCompanion(
          status: Value(newStatus),
          statusHistory: Value(statusHistoryJson),
          version: Value(newVersion),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'job',
          entityId: jobId,
          operation: 'UPDATE',
          payload: {
            'id': jobId,
            'new_status': newStatus,
            'status_history': statusHistoryJson,
            'version': newVersion,
          },
        ),
      );
    });
  }

  /// Update job fields and atomically enqueue an UPDATE sync item.
  Future<void> updateJob(String jobId, JobsCompanion companion) async {
    await db.transaction(() async {
      await (update(jobs)..where((tbl) => tbl.id.equals(jobId)))
          .write(companion);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'job',
          entityId: jobId,
          operation: 'UPDATE',
          payload: _jobCompanionPayload(jobId, companion),
        ),
      );
    });
  }

  /// Report a delay on a job — updates scheduled_completion_date and appends
  /// a delay entry to status_history in a single atomic transaction.
  ///
  /// Steps:
  ///   1. Reads current job from Drift to get existing statusHistory.
  ///   2. Decodes statusHistory JSON, appends the new delay entry, re-encodes.
  ///   3. In a single transaction: updates the job row (scheduledCompletionDate,
  ///      statusHistory, version+1, updatedAt) AND inserts a sync queue entry.
  ///
  /// The delay does NOT change job.status — the job stays scheduled/in_progress.
  /// Multiple delays are allowed; each creates a new status_history entry.
  /// The latest new_eta overwrites scheduledCompletionDate.
  ///
  /// Uses the transactional outbox dual-write pattern (same as all mutations).
  Future<void> reportDelay({
    required String jobId,
    required String reason,
    required DateTime newEta,
    required String currentUserId,
    required int currentVersion,
  }) async {
    final now = DateTime.now();

    // Decode existing statusHistory and append the new delay entry.
    final existingRow = await (select(jobs)
          ..where((tbl) => tbl.id.equals(jobId)))
        .getSingleOrNull();

    final existingHistory = <Map<String, dynamic>>[];
    if (existingRow != null) {
      try {
        final decoded =
            jsonDecode(existingRow.statusHistory) as List<dynamic>;
        existingHistory.addAll(decoded.whereType<Map<String, dynamic>>());
      } catch (e) {
        // Malformed JSON — start fresh (defensive; preserves new delay entry).
        debugPrint('[JobDao.reportDelay] Failed to decode statusHistory: $e');
      }
    }

    // Append the delay entry.
    existingHistory.add({
      'type': 'delay',
      'reason': reason,
      'new_eta': newEta.toIso8601String().substring(0, 10),
      'timestamp': now.toUtc().toIso8601String(),
      'user_id': currentUserId,
    });

    final newStatusHistoryJson = jsonEncode(existingHistory);
    final newVersion = currentVersion + 1;
    // Normalize ETA to midnight UTC for Drift DATE storage.
    final newEtaNormalized =
        DateTime.utc(newEta.year, newEta.month, newEta.day);

    await db.transaction(() async {
      await (update(jobs)..where((tbl) => tbl.id.equals(jobId))).write(
        JobsCompanion(
          scheduledCompletionDate: Value(newEtaNormalized),
          statusHistory: Value(newStatusHistoryJson),
          version: Value(newVersion),
          updatedAt: Value(now),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'job',
          entityId: jobId,
          operation: 'UPDATE',
          payload: {
            'id': jobId,
            'scheduled_completion_date': newEtaNormalized.toIso8601String(),
            'status_history': newStatusHistoryJson,
            'version': newVersion,
            'updated_at': now.toIso8601String(),
          },
        ),
      );
    });
  }

  /// Update a job's GPS coordinates and atomically enqueue an UPDATE sync item.
  ///
  /// Sets [gpsLatitude] and [gpsLongitude] from device location capture.
  /// Sets [gpsAddress] to null — the backend will reverse-geocode the coordinates
  /// and populate the address field, which flows back via sync pull.
  ///
  /// The sync payload includes gps_address=null to signal the backend to geocode.
  Future<void> updateJobGps({
    required String jobId,
    required double latitude,
    required double longitude,
  }) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (update(jobs)..where((tbl) => tbl.id.equals(jobId))).write(
        JobsCompanion(
          gpsLatitude: Value(latitude),
          gpsLongitude: Value(longitude),
          gpsAddress: const Value(null),
          updatedAt: Value(now),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'job',
          entityId: jobId,
          operation: 'UPDATE',
          payload: {
            'id': jobId,
            'gps_latitude': latitude,
            'gps_longitude': longitude,
            'gps_address': null,
            'updated_at': now.toIso8601String(),
          },
        ),
      );
    });
  }

  /// Soft-delete a job and atomically enqueue a DELETE sync item.
  ///
  /// The job remains in the local DB as a tombstone — sync propagates
  /// the deletedAt timestamp to other devices.
  Future<void> softDeleteJob(String jobId) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (update(jobs)..where((tbl) => tbl.id.equals(jobId))).write(
        JobsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'job',
          entityId: jobId,
          operation: 'DELETE',
          payload: {'id': jobId, 'deleted_at': now.toIso8601String()},
        ),
      );
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // JobRequest streams and mutations
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of pending job requests for admin review queue.
  Stream<List<JobRequestEntity>> watchPendingRequestsByCompany(
      String companyId) {
    return (select(jobRequests)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) &
                tbl.requestStatus.equals('pending') &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch()
        .map((rows) => rows.map(_rowToJobRequestEntity).toList());
  }

  /// Insert a new job request and atomically enqueue a CREATE sync item.
  Future<void> insertJobRequest(JobRequestsCompanion entry) async {
    await db.transaction(() async {
      await into(jobRequests).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'job_request',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _jobRequestPayload(entry),
        ),
      );
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // ClientProfile streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of all active client profiles for a company.
  Stream<List<ClientProfileEntity>> watchClientProfiles(String companyId) {
    return (select(clientProfiles)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .watch()
        .map((rows) => rows.map(_rowToClientProfileEntity).toList());
  }

  /// Insert a new client profile and atomically enqueue a CREATE sync item.
  ///
  /// Called when a user is assigned the 'client' role via Team Management.
  Future<void> insertClientProfile(ClientProfilesCompanion entry) async {
    await db.transaction(() async {
      await into(clientProfiles).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'client_profile',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: {
            'id': entry.id.value,
            'companyId': entry.companyId.value,
            'userId': entry.userId.value,
            if (entry.version.present) 'version': entry.version.value,
            if (entry.createdAt.present)
              'createdAt': entry.createdAt.value.toIso8601String(),
            if (entry.updatedAt.present)
              'updatedAt': entry.updatedAt.value.toIso8601String(),
          },
        ),
      );
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // Sync pull upsert
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert a job from a sync pull response (server-wins on conflict).
  Future<void> upsertJobFromSync(JobsCompanion companion) async {
    await into(jobs).insertOnConflictUpdate(companion);
  }

  /// Upsert a client profile from a sync pull response.
  Future<void> upsertClientProfileFromSync(
      ClientProfilesCompanion companion) async {
    await into(clientProfiles).insertOnConflictUpdate(companion);
  }

  /// Upsert a client property from a sync pull response.
  Future<void> upsertClientPropertyFromSync(
      ClientPropertiesCompanion companion) async {
    await into(clientProperties).insertOnConflictUpdate(companion);
  }

  /// Upsert a job request from a sync pull response.
  Future<void> upsertJobRequestFromSync(
      JobRequestsCompanion companion) async {
    await into(jobRequests).insertOnConflictUpdate(companion);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ────────────────────────────────────────────────────────────────────────

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

  /// Build a JSON-serializable payload from a [JobsCompanion] (for CREATE).
  Map<String, dynamic> _jobPayload(JobsCompanion entry) {
    return {
      'id': entry.id.value,
      'company_id': entry.companyId.value,
      if (entry.clientId.present) 'client_id': entry.clientId.value,
      if (entry.contractorId.present)
        'contractor_id': entry.contractorId.value,
      'description': entry.description.value,
      'trade_type': entry.tradeType.value,
      'status': entry.status.present ? entry.status.value : 'quote',
      'status_history':
          entry.statusHistory.present ? entry.statusHistory.value : '[]',
      'priority': entry.priority.present ? entry.priority.value : 'medium',
      if (entry.purchaseOrderNumber.present)
        'purchase_order_number': entry.purchaseOrderNumber.value,
      if (entry.externalReference.present)
        'external_reference': entry.externalReference.value,
      'tags': entry.tags.present ? entry.tags.value : '[]',
      if (entry.notes.present) 'notes': entry.notes.value,
      if (entry.estimatedDurationMinutes.present)
        'estimated_duration_minutes': entry.estimatedDurationMinutes.value,
      if (entry.scheduledCompletionDate.present &&
          entry.scheduledCompletionDate.value != null)
        'scheduled_completion_date':
            entry.scheduledCompletionDate.value!.toIso8601String(),
      'version': entry.version.present ? entry.version.value : 1,
      if (entry.createdAt.present)
        'created_at': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updated_at': entry.updatedAt.value.toIso8601String(),
    };
  }

  /// Build a JSON-serializable payload from a [JobsCompanion] (for UPDATE).
  Map<String, dynamic> _jobCompanionPayload(
      String jobId, JobsCompanion companion) {
    return {
      'id': jobId,
      if (companion.clientId.present) 'client_id': companion.clientId.value,
      if (companion.contractorId.present)
        'contractor_id': companion.contractorId.value,
      if (companion.description.present)
        'description': companion.description.value,
      if (companion.tradeType.present) 'trade_type': companion.tradeType.value,
      if (companion.status.present) 'status': companion.status.value,
      if (companion.priority.present) 'priority': companion.priority.value,
      if (companion.purchaseOrderNumber.present)
        'purchase_order_number': companion.purchaseOrderNumber.value,
      if (companion.externalReference.present)
        'external_reference': companion.externalReference.value,
      if (companion.tags.present) 'tags': companion.tags.value,
      if (companion.notes.present) 'notes': companion.notes.value,
      if (companion.estimatedDurationMinutes.present)
        'estimated_duration_minutes':
            companion.estimatedDurationMinutes.value,
      if (companion.scheduledCompletionDate.present &&
          companion.scheduledCompletionDate.value != null)
        'scheduled_completion_date':
            companion.scheduledCompletionDate.value!.toIso8601String(),
      if (companion.version.present) 'version': companion.version.value,
      if (companion.updatedAt.present)
        'updated_at': companion.updatedAt.value.toIso8601String(),
    };
  }

  /// Build a JSON-serializable payload from a [JobRequestsCompanion] (for CREATE).
  Map<String, dynamic> _jobRequestPayload(JobRequestsCompanion entry) {
    return {
      'id': entry.id.value,
      'company_id': entry.companyId.value,
      if (entry.clientId.present) 'client_id': entry.clientId.value,
      'description': entry.description.value,
      if (entry.tradeType.present) 'trade_type': entry.tradeType.value,
      'urgency': entry.urgency.present ? entry.urgency.value : 'normal',
      if (entry.preferredDateStart.present &&
          entry.preferredDateStart.value != null)
        'preferred_date_start':
            entry.preferredDateStart.value!.toIso8601String(),
      if (entry.preferredDateEnd.present &&
          entry.preferredDateEnd.value != null)
        'preferred_date_end': entry.preferredDateEnd.value!.toIso8601String(),
      if (entry.budgetMin.present) 'budget_min': entry.budgetMin.value,
      if (entry.budgetMax.present) 'budget_max': entry.budgetMax.value,
      'photos': entry.photos.present ? entry.photos.value : '[]',
      if (entry.submittedName.present)
        'submitted_name': entry.submittedName.value,
      if (entry.submittedEmail.present)
        'submitted_email': entry.submittedEmail.value,
      if (entry.submittedPhone.present)
        'submitted_phone': entry.submittedPhone.value,
      'version': entry.version.present ? entry.version.value : 1,
      if (entry.createdAt.present)
        'created_at': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updated_at': entry.updatedAt.value.toIso8601String(),
    };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Row to entity mappers
  // ────────────────────────────────────────────────────────────────────────

  /// Map a Drift [Job] row to a [JobEntity] domain object.
  ///
  /// Decodes [statusHistory] and [tags] from JSON TEXT columns.
  JobEntity _rowToJobEntity(Job row) {
    List<Map<String, dynamic>> statusHistory;
    try {
      final decoded = jsonDecode(row.statusHistory) as List<dynamic>;
      statusHistory = decoded
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      statusHistory = [];
    }

    List<String> tags;
    try {
      final decoded = jsonDecode(row.tags) as List<dynamic>;
      tags = decoded.whereType<String>().toList();
    } catch (_) {
      tags = [];
    }

    return JobEntity(
      id: row.id,
      companyId: row.companyId,
      clientId: row.clientId,
      contractorId: row.contractorId,
      description: row.description,
      tradeType: row.tradeType,
      status: row.status,
      statusHistory: statusHistory,
      priority: row.priority,
      purchaseOrderNumber: row.purchaseOrderNumber,
      externalReference: row.externalReference,
      tags: tags,
      notes: row.notes,
      estimatedDurationMinutes: row.estimatedDurationMinutes,
      scheduledCompletionDate: row.scheduledCompletionDate,
      gpsLatitude: row.gpsLatitude,
      gpsLongitude: row.gpsLongitude,
      gpsAddress: row.gpsAddress,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  /// Map a Drift [JobRequest] row to a [JobRequestEntity] domain object.
  JobRequestEntity _rowToJobRequestEntity(JobRequest row) {
    List<String> photos;
    try {
      final decoded = jsonDecode(row.photos) as List<dynamic>;
      photos = decoded.whereType<String>().toList();
    } catch (_) {
      photos = [];
    }

    return JobRequestEntity(
      id: row.id,
      companyId: row.companyId,
      clientId: row.clientId,
      description: row.description,
      tradeType: row.tradeType,
      urgency: row.urgency,
      preferredDateStart: row.preferredDateStart,
      preferredDateEnd: row.preferredDateEnd,
      budgetMin: row.budgetMin,
      budgetMax: row.budgetMax,
      photos: photos,
      requestStatus: row.requestStatus,
      declineReason: row.declineReason,
      declineMessage: row.declineMessage,
      convertedJobId: row.convertedJobId,
      submittedName: row.submittedName,
      submittedEmail: row.submittedEmail,
      submittedPhone: row.submittedPhone,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  /// Map a Drift [ClientProfile] row to a [ClientProfileEntity] domain object.
  ClientProfileEntity _rowToClientProfileEntity(ClientProfile row) {
    List<String> tags;
    try {
      final decoded = jsonDecode(row.tags) as List<dynamic>;
      tags = decoded.whereType<String>().toList();
    } catch (_) {
      tags = [];
    }

    return ClientProfileEntity(
      id: row.id,
      companyId: row.companyId,
      userId: row.userId,
      billingAddress: row.billingAddress,
      tags: tags,
      adminNotes: row.adminNotes,
      referralSource: row.referralSource,
      preferredContractorId: row.preferredContractorId,
      preferredContactMethod: row.preferredContactMethod,
      averageRating: row.averageRating,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }
}
