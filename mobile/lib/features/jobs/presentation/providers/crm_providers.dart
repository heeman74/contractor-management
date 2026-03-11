import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to legacy in Riverpod 3 — explicitly imported.
// ignore: depend_on_referenced_packages
import 'package:riverpod/legacy.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../domain/client_profile_entity.dart';
import '../../domain/job_entity.dart';
import '../../domain/job_request_entity.dart';

/// Reactive stream of all active client profiles for a company.
///
/// Watches the local Drift [ClientProfiles] table — offline-first pattern.
/// Notified automatically when sync writes new/updated profiles to local DB.
final clientListNotifierProvider = StreamProvider.autoDispose
    .family<List<ClientProfileEntity>, String>((ref, companyId) {
  final jobDao = getIt<JobDao>();
  return jobDao.watchClientProfiles(companyId);
});

/// Reactive stream of pending job requests awaiting admin review.
///
/// Watches [JobRequests] where requestStatus == 'pending' for the given company.
/// Ordered by created_at ASC (oldest first = highest review priority).
final pendingRequestsNotifierProvider = StreamProvider.autoDispose
    .family<List<JobRequestEntity>, String>((ref, companyId) {
  final jobDao = getIt<JobDao>();
  return jobDao.watchPendingRequestsByCompany(companyId);
});

/// Reactive stream of all jobs for a specific client.
///
/// Family provider parameterized by [clientId].
/// Used in the CRM client detail screen to show a client's full job history.
final clientJobHistoryNotifierProvider = StreamProvider.autoDispose
    .family<List<JobEntity>, String>((ref, clientId) {
  final jobDao = getIt<JobDao>();
  return jobDao.watchJobsByClient(clientId);
});

/// StateProvider for the client list search query.
///
/// Updated by the search bar in [ClientCrmScreen]. Providers that
/// render the filtered list should filter [clientListNotifierProvider]
/// results against this query string.
final clientSearchQueryProvider = StateProvider<String>((ref) => '');
