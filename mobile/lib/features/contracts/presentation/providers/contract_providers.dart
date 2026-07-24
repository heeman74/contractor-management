import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/contract_repository.dart';
import '../../domain/contract.dart';

/// Provider exposing the [ContractRepository], built on the shared, auth-aware
/// Dio instance from GetIt.
///
/// NOTE: GetIt is used here because [DioClient] is a network singleton
/// registered at startup in service_locator.dart. Riverpod providers read it
/// through this factory. (CLAUDE.md: document GetIt<->Riverpod tradeoffs.)
final contractRepositoryProvider = Provider<ContractRepository>((ref) {
  return ContractRepository(dio: getIt<DioClient>().instance);
});

/// Fetch a single contract by id.
///
/// `autoDispose.family` — one instance per contract id, disposed when no
/// longer watched. `ref.invalidate(contractProvider(id))` refreshes it after
/// signing completes.
final contractProvider =
    FutureProvider.autoDispose.family<Contract, String>((ref, contractId) {
  return ref.watch(contractRepositoryProvider).getContract(contractId);
});

/// Fetch a fresh embedded signing URL for a contract id.
///
/// Kept separate from [contractProvider] so the URL can be re-fetched (a fresh
/// signing session) without re-loading the whole contract, and vice-versa.
final signUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, contractId) {
  return ref.watch(contractRepositoryProvider).getSignUrl(contractId);
});
