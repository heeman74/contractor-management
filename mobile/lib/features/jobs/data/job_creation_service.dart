import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/job_priority.dart';
import '../domain/job_status.dart';

/// User-entered values collected by the job creation wizard.
class JobDraft {
  const JobDraft({
    required this.description,
    required this.tradeType,
    this.priority = JobPriority.medium,
    this.clientId,
    this.contractorId,
    this.notes,
    this.estimatedDurationMinutes,
    this.preferredDate,
  });

  final String description;
  final String tradeType;
  final String priority;
  final String? clientId;
  final String? contractorId;
  final String? notes;
  final int? estimatedDurationMinutes;
  final DateTime? preferredDate;
}

/// Creates jobs offline-first via [JobDao].
///
/// Encapsulates the companion-building and status-history bootstrapping that
/// previously lived inside the wizard widget's `_submit` method.
class JobCreationService {
  JobCreationService({required JobDao jobDao, Uuid uuid = const Uuid()})
      : _jobDao = jobDao,
        _uuid = uuid;

  static const String _emptyTagsJson = '[]';
  static const int _initialVersion = 1;

  final JobDao _jobDao;
  final Uuid _uuid;

  /// Persists a new job at the Quote stage and returns its generated id.
  Future<String> createJob({
    required String companyId,
    required String userId,
    required JobDraft draft,
  }) async {
    final jobId = _uuid.v4();
    final now = DateTime.now();

    await _jobDao.insertJob(
      JobsCompanion(
        id: Value(jobId),
        companyId: Value(companyId),
        description: Value(draft.description),
        tradeType: Value(draft.tradeType),
        status: Value(JobStatus.quote.backendValue),
        statusHistory: Value(_initialStatusHistory(userId, now)),
        priority: Value(draft.priority),
        tags: const Value(_emptyTagsJson),
        version: const Value(_initialVersion),
        createdAt: Value(now),
        updatedAt: Value(now),
        clientId: Value(draft.clientId),
        contractorId: Value(draft.contractorId),
        notes: Value(draft.notes),
        estimatedDurationMinutes: Value(draft.estimatedDurationMinutes),
        scheduledCompletionDate: Value(draft.preferredDate),
      ),
    );
    return jobId;
  }

  String _initialStatusHistory(String userId, DateTime timestamp) {
    return jsonEncode([
      {
        'status': JobStatus.quote.backendValue,
        'timestamp': timestamp.toIso8601String(),
        'user_id': userId,
      }
    ]);
  }
}
