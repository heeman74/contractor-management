/// Unit tests for [JobCreationService] using a real in-memory Drift database.
///
/// Covers the job-creation logic extracted out of the wizard widget:
/// 1. createJob persists a job at Quote stage with the draft fields
/// 2. the initial status history records a 'quote' entry for the acting user
/// 3. optional fields (client/contractor/notes/date) round-trip correctly
library;

import 'dart:convert';

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/features/jobs/data/job_creation_service.dart';
import 'package:contractorhub/features/jobs/domain/job_priority.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

const _companyId = 'co-1';
const _userId = 'user-1';

Future<void> _seedCompany(AppDatabase db) {
  final now = DateTime.now();
  return db.companyDao.insertCompany(CompaniesCompanion.insert(
    id: const Value(_companyId),
    name: 'Company',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<Job?> _jobById(AppDatabase db, String id) {
  return (db.select(db.jobs)..where((j) => j.id.equals(id)))
      .getSingleOrNull();
}

void main() {
  late AppDatabase db;
  late JobCreationService service;

  setUp(() async {
    db = _openTestDb();
    await _seedCompany(db);
    service = JobCreationService(jobDao: db.jobDao);
  });

  tearDown(() async => db.close());

  test('persists a job at Quote stage with the draft fields', () async {
    final jobId = await service.createJob(
      companyId: _companyId,
      userId: _userId,
      draft: const JobDraft(
        description: 'Replace water heater',
        tradeType: 'Plumbing',
        priority: JobPriority.high,
      ),
    );

    final job = await _jobById(db, jobId);
    expect(job, isNotNull);
    expect(job!.status, 'quote');
    expect(job.description, 'Replace water heater');
    expect(job.tradeType, 'Plumbing');
    expect(job.priority, JobPriority.high);
    expect(job.version, 1);
  });

  test('records an initial quote status-history entry for the actor', () async {
    final jobId = await service.createJob(
      companyId: _companyId,
      userId: _userId,
      draft: const JobDraft(
        description: 'Install lighting',
        tradeType: 'Electrical',
      ),
    );

    final job = await _jobById(db, jobId);
    final history = jsonDecode(job!.statusHistory) as List<dynamic>;
    expect(history, hasLength(1));
    expect(history.first['status'], 'quote');
    expect(history.first['user_id'], _userId);
    expect(history.first['timestamp'], isA<String>());
  });

  test('round-trips optional client, contractor, notes and date', () async {
    final preferredDate = DateTime(2025, 8);
    final jobId = await service.createJob(
      companyId: _companyId,
      userId: _userId,
      draft: JobDraft(
        description: 'Deck repair job',
        tradeType: 'Carpentry',
        clientId: 'client-9',
        contractorId: 'contractor-9',
        notes: 'Bring extra decking',
        estimatedDurationMinutes: 240,
        preferredDate: preferredDate,
      ),
    );

    final job = await _jobById(db, jobId);
    expect(job!.clientId, 'client-9');
    expect(job.contractorId, 'contractor-9');
    expect(job.notes, 'Bring extra decking');
    expect(job.estimatedDurationMinutes, 240);
    expect(job.scheduledCompletionDate, preferredDate);
  });

  test('defaults priority to medium and notes to null when omitted', () async {
    final jobId = await service.createJob(
      companyId: _companyId,
      userId: _userId,
      draft: const JobDraft(
        description: 'General handywork',
        tradeType: 'General',
      ),
    );

    final job = await _jobById(db, jobId);
    expect(job!.priority, JobPriority.medium);
    expect(job.notes, isNull);
    expect(job.clientId, isNull);
    expect(job.contractorId, isNull);
  });
}
