import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../data/checklist_repository.dart';

// ────────────────────────────────────────────────────────────────────────
// Infrastructure providers
// ────────────────────────────────────────────────────────────────────────

/// Provides the [ChecklistRepository] instance.
///
/// Uses GetIt for [DioClient] and [AppDatabase] (registered in service_locator)
/// to construct the repository. This mixes GetIt and Riverpod — intentional
/// because the app's sync infrastructure is GetIt-managed; documented here
/// per CLAUDE.md rule.
final checklistRepositoryProvider = Provider<ChecklistRepository>((ref) {
  final db = getIt<AppDatabase>();
  final dioClient = getIt<DioClient>();
  return ChecklistRepository(db.dailyChecklistDao, dioClient);
});

// ────────────────────────────────────────────────────────────────────────
// Today's checklist stream provider
// ────────────────────────────────────────────────────────────────────────

/// Reactive stream of today's AI-generated checklist items for the current contractor.
///
/// - Watches [DailyChecklists] rows for the current user's contractor ID and company ID.
/// - On first subscription, triggers a background API fetch to refresh data.
/// - Auto-disposed when no widgets are watching.
/// - Uses a [Completer]-based guard to prevent concurrent fetches.
///
/// Usage:
/// ```dart
/// final checklists = ref.watch(todayChecklistProvider);
/// ```
final todayChecklistProvider =
    StreamProvider.autoDispose<List<DailyChecklist>>((ref) {
  final authState = ref.watch(authNotifierProvider);

  if (authState is! AuthAuthenticated) {
    return const Stream.empty();
  }

  final contractorId = authState.userId;
  final companyId = authState.companyId;
  final repository = ref.watch(checklistRepositoryProvider);

  // Deduplicated background fetch — prevents concurrent API calls when
  // multiple widgets subscribe or the provider rebuilds rapidly.
  Completer<void>? fetchGuard;
  Future.microtask(() async {
    if (fetchGuard != null) return; // already in flight
    fetchGuard = Completer<void>();
    try {
      await repository.fetchTodayChecklist();
    } catch (e) {
      debugPrint('todayChecklistProvider: fetch error — $e');
    } finally {
      fetchGuard?.complete();
      fetchGuard = null;
    }
  });

  return repository.watchTodayChecklist(contractorId, companyId: companyId);
});
