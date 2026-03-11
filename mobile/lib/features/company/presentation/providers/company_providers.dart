import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/company_entity.dart';

/// Reactive stream of all companies from the local Drift database.
///
/// Offline-first pattern: UI watches this stream, HTTP sync (Phase 2)
/// writes to the local DB, which automatically notifies this stream.
final companiesProvider =
    StreamProvider.autoDispose<List<CompanyEntity>>((ref) {
  final db = getIt<AppDatabase>();
  return db.companyDao.watchAllCompanies();
});

/// Stream of a single company by ID.
///
/// Returns null if the company is not found in the local DB.
final companyProvider = StreamProvider.autoDispose
    .family<CompanyEntity?, String>((ref, companyId) {
  final db = getIt<AppDatabase>();
  return db.companyDao
      .watchAllCompanies()
      .map((list) => list.where((c) => c.id == companyId).firstOrNull);
});
