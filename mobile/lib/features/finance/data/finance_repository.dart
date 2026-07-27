import '../../../core/network/dio_client.dart';
import 'cost_breakdown.dart';
import 'cost_entry_dao.dart';
import 'cost_receipt_dao.dart';

/// On-demand Dio repository for cost entries, categories, and receipts.
///
/// Per 31-RESEARCH.md Pitfall 2, cost data is NEVER pulled via the
/// company-wide /sync delta — every read here is an explicit, on-demand
/// GET scoped to one job/trade-scope/project/cost-entry, gated server-side
/// by finance.view. Results are upserted into local Drift tables so the
/// offline-first UI (job detail, trade scope detail, project Costs tab —
/// landing in 31-05) can render from local storage post-fetch.
///
/// `CostEntryResponse`/`CostReceiptResponse` do not carry company_id (they
/// extend `BaseResponseSchema`, not `TenantResponseSchema`) — callers pass
/// [companyId] explicitly, matching the DAO convention used throughout the
/// codebase (e.g. `NoteDao.insertNote`).
class FinanceRepository {
  final DioClient _dioClient;
  final CostEntryDao _costEntryDao;
  final CostReceiptDao _costReceiptDao;

  FinanceRepository({
    required DioClient dioClient,
    required CostEntryDao costEntryDao,
    required CostReceiptDao costReceiptDao,
  })  : _dioClient = dioClient,
        _costEntryDao = costEntryDao,
        _costReceiptDao = costReceiptDao;

  /// Fetch and upsert cost entries anchored to [jobId].
  ///
  /// GET /cost-entries/?job_id={jobId}
  Future<void> fetchCostEntriesForJob(String companyId, String jobId) async {
    final response = await _dioClient.instance.get<dynamic>(
      '/cost-entries/',
      queryParameters: {'job_id': jobId},
    );
    await _upsertCostEntries(companyId, response.data);
  }

  /// Fetch and upsert cost entries anchored to [tradeScopeId].
  ///
  /// GET /cost-entries/?trade_scope_id={tradeScopeId}
  Future<void> fetchCostEntriesForTradeScope(
    String companyId,
    String tradeScopeId,
  ) async {
    final response = await _dioClient.instance.get<dynamic>(
      '/cost-entries/',
      queryParameters: {'trade_scope_id': tradeScopeId},
    );
    await _upsertCostEntries(companyId, response.data);
  }

  /// Fetch and upsert the itemized cost entries backing a project's rollup.
  ///
  /// GET /projects/{projectId}/cost-entries
  ///
  /// Returns the authoritative backend-computed [ProjectCostRollupFetch.total]
  /// (a Decimal-as-string, e.g. "1250.00") for display — per
  /// 31-RESEARCH.md Pitfall 5, any locally-summed double total is a display
  /// estimate only, never authoritative — plus the distinct
  /// [ProjectCostRollupFetch.jobIds] found in the response, since the mobile
  /// `Jobs` table carries no `projectId` FK (31-04 decision):
  /// `CostEntryDao.watchByProject` needs an explicit `jobIds` list from the
  /// caller to include job-anchored entries in its local reactive query, and
  /// this on-demand fetch is the only place that job-anchored membership for
  /// a project is known on mobile.
  Future<ProjectCostRollupFetch> fetchProjectRollup(
    String companyId,
    String projectId,
  ) async {
    final response = await _dioClient.instance.get<dynamic>(
      '/projects/$projectId/cost-entries',
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException(
        'Expected a Map response from the project cost rollup endpoint',
      );
    }

    final entries = data['entries'];
    if (entries is! List) {
      throw const FormatException(
        'Missing "entries" list in project cost rollup response',
      );
    }
    await _upsertCostEntries(companyId, entries);

    final total = data['total'];
    if (total is! String) {
      throw const FormatException(
        'Missing "total" string in project cost rollup response',
      );
    }

    final jobIds = entries
        .whereType<Map<String, dynamic>>()
        .map((entry) => entry['job_id'])
        .whereType<String>()
        .toSet()
        .toList();

    return ProjectCostRollupFetch(
      total: total,
      jobIds: jobIds,
      breakdown: CostBreakdown.tryFromJson(data),
    );
  }

  /// Fetch the itemized cost breakdown for a job.
  ///
  /// GET /jobs/{jobId}/cost-breakdown
  ///
  /// Not persisted to Drift: labor cost requires server-side rate resolution
  /// and labor rate data never reaches the device (rates are the most
  /// sensitive data in the system). Callers show the cached CostListSection
  /// immediately and layer this on when it lands.
  Future<CostBreakdown> fetchJobCostBreakdown(String jobId) =>
      _fetchCostBreakdown('/jobs/$jobId/cost-breakdown');

  /// Fetch the itemized cost breakdown for a trade scope.
  ///
  /// GET /trade-scopes/{tradeScopeId}/cost-breakdown
  Future<CostBreakdown> fetchTradeScopeCostBreakdown(String tradeScopeId) =>
      _fetchCostBreakdown('/trade-scopes/$tradeScopeId/cost-breakdown');

  Future<CostBreakdown> _fetchCostBreakdown(String path) async {
    final response = await _dioClient.instance.get<dynamic>(path);
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException(
        'Expected a Map response from the cost-breakdown endpoint',
      );
    }
    return CostBreakdown.fromJson(data);
  }

  /// Fetch the tenant's cost categories lookup (materials/subcontractor/
  /// other/labor).
  ///
  /// GET /cost-categories/
  ///
  /// Not persisted to Drift — this plan ships no local cost_categories
  /// table (categories change rarely; the field-capture screens land in
  /// 31-05 and may add local caching there if offline category selection
  /// proves necessary).
  Future<List<Map<String, dynamic>>> fetchCostCategories() async {
    final response =
        await _dioClient.instance.get<dynamic>('/cost-categories/');
    final data = response.data;
    if (data is! List) {
      throw const FormatException(
        'Expected a List response from the cost-categories endpoint',
      );
    }
    return data.whereType<Map<String, dynamic>>().toList();
  }

  /// Fetch and upsert receipts for a cost entry.
  ///
  /// GET /cost-entries/{costEntryId}/receipts
  Future<void> fetchReceipts(String companyId, String costEntryId) async {
    final response = await _dioClient.instance.get<dynamic>(
      '/cost-entries/$costEntryId/receipts',
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException(
        'Expected a List response from the cost-entry receipts endpoint',
      );
    }
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      await _costReceiptDao.upsertFromRemote({...item, 'company_id': companyId});
    }
  }

  Future<void> _upsertCostEntries(String companyId, dynamic data) async {
    if (data is! List) {
      throw const FormatException(
        'Expected a List response from the cost-entries endpoint',
      );
    }
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      await _costEntryDao.upsertFromRemote({...item, 'company_id': companyId});
    }
  }
}

/// Result of [FinanceRepository.fetchProjectRollup]: the authoritative
/// backend total plus the distinct job IDs seen in the response (used by
/// callers to build the `jobIds` argument for
/// [CostEntryDao.watchByProject]).
class ProjectCostRollupFetch {
  const ProjectCostRollupFetch({
    required this.total,
    required this.jobIds,
    this.breakdown,
  });

  /// Decimal-as-string backend-computed total (e.g. "1250.00").
  final String total;

  /// Distinct job IDs anchoring at least one entry in this project's rollup.
  final List<String> jobIds;

  /// Itemized breakdown from the Phase 32 additive rollup fields — null when
  /// the backend predates them (tolerant parse; the strict total/entries
  /// contract above is unchanged).
  final CostBreakdown? breakdown;
}
