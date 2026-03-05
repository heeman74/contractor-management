import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/company_entity.dart';

part 'company_providers.g.dart';

/// Reactive stream of all companies from the local Drift database.
///
/// Offline-first pattern: UI watches this stream, HTTP sync (Phase 2)
/// writes to the local DB, which automatically notifies this stream.
///
/// Usage:
/// ```dart
/// final companiesAsync = ref.watch(companiesProvider);
/// companiesAsync.when(
///   data: (companies) => ...,
///   loading: () => ...,
///   error: (e, st) => ...,
/// );
/// ```
@riverpod
Stream<List<CompanyEntity>> companies(Ref ref) {
  final db = getIt<AppDatabase>();
  return db.companyDao.watchAllCompanies();
}

/// Stream of a single company by ID.
///
/// Returns null if the company is not found in the local DB.
@riverpod
Stream<CompanyEntity?> company(Ref ref, String companyId) {
  final db = getIt<AppDatabase>();
  return db.companyDao
      .watchAllCompanies()
      .map((list) => list.where((c) => c.id == companyId).firstOrNull);
}
