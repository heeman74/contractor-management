"use client";

import { apiGet, apiPost, apiPatch, apiDelete, apiUpload } from "@/lib/api-client";
import type {
  CostEntry,
  CostCategory,
  CostReceipt,
  ProjectCostRollup,
  CostEntryInput,
  CostEntryPatch,
  LaborRate,
  LaborRateInput,
  CategoryTotal,
  LaborCostSummary,
  CostBreakdown,
  MarginSummary,
  RevenueBasis,
  BudgetVsActual,
  PortfolioTotals,
  ProjectFinancialsRow,
  AttentionRow,
  AttentionTier,
  CompanyFinancials,
  ScopeBudgetRow,
  ProjectFinancials,
  TrendBucket,
  TrendWindow,
  MarginTrend,
  FindingSeverity,
  ProfitabilityFinding,
} from "./types";
import { TREND_WINDOWS } from "./types";

// --- Raw API response shapes (snake_case, mirroring backend schemas) ---

interface CostEntryApiResponse {
  id: string;
  job_id: string | null;
  trade_scope_id: string | null;
  category_id: string;
  category_name?: string | null;
  amount: string;
  incurred_date: string;
  vendor?: string | null;
  note?: string | null;
  created_at: string;
  updated_at: string;
}

interface CostCategoryApiResponse {
  id: string;
  name: string;
  is_system: boolean;
}

interface CostReceiptApiResponse {
  id: string;
  cost_entry_id: string;
  remote_url: string;
  caption?: string | null;
  created_at: string;
}

interface CategoryTotalApiResponse {
  category_id: string;
  category_name: string;
  total: string;
}

interface LaborCostSummaryApiResponse {
  total: string;
  rated_seconds: number;
  unrated_seconds: number;
  basis: string;
}

interface MarginSummaryApiResponse {
  revenue: string | null;
  revenue_basis: string;
  margin: string | null;
  margin_percent: string | null;
  incomplete: boolean;
  incomplete_reasons: string[];
}

interface BudgetVsActualApiResponse {
  budget_id: string;
  total: string;
  spent: string;
  remaining: string;
  percent_used: string;
}

interface CostBreakdownApiResponse {
  categories: CategoryTotalApiResponse[];
  labor: LaborCostSummaryApiResponse | null;
  labor_tracked_at_job_level: boolean;
  grand_total: string;
  margin?: MarginSummaryApiResponse | null;
  budget?: BudgetVsActualApiResponse | null;
}

interface ProjectCostRollupApiResponse {
  project_id: string;
  total: string;
  entries: CostEntryApiResponse[];
  categories?: CategoryTotalApiResponse[];
  labor?: LaborCostSummaryApiResponse | null;
  grand_total?: string;
  margin?: MarginSummaryApiResponse | null;
  budget?: BudgetVsActualApiResponse | null;
}

// --- snake_case -> camelCase mappers ---

function mapCostEntry(raw: CostEntryApiResponse): CostEntry {
  return {
    id: raw.id,
    jobId: raw.job_id,
    tradeScopeId: raw.trade_scope_id,
    categoryId: raw.category_id,
    categoryName: raw.category_name ?? null,
    amount: raw.amount,
    incurredDate: raw.incurred_date,
    vendor: raw.vendor ?? null,
    note: raw.note ?? null,
    createdAt: raw.created_at,
    updatedAt: raw.updated_at,
  };
}

function mapCostCategory(raw: CostCategoryApiResponse): CostCategory {
  return { id: raw.id, name: raw.name, isSystem: raw.is_system };
}

function mapCostReceipt(raw: CostReceiptApiResponse): CostReceipt {
  return {
    id: raw.id,
    costEntryId: raw.cost_entry_id,
    remoteUrl: raw.remote_url,
    caption: raw.caption ?? null,
    createdAt: raw.created_at,
  };
}

function mapCategoryTotal(raw: CategoryTotalApiResponse): CategoryTotal {
  return {
    categoryId: raw.category_id,
    categoryName: raw.category_name,
    total: raw.total,
  };
}

function mapLaborSummary(
  raw: LaborCostSummaryApiResponse | null | undefined
): LaborCostSummary | null {
  if (!raw) return null;
  return {
    total: raw.total,
    ratedSeconds: raw.rated_seconds,
    unratedSeconds: raw.unrated_seconds,
    basis: raw.basis,
  };
}

function mapMarginSummary(
  raw: MarginSummaryApiResponse | null | undefined
): MarginSummary | null {
  if (!raw) return null;
  return {
    revenue: raw.revenue,
    revenueBasis: raw.revenue_basis as RevenueBasis,
    margin: raw.margin,
    marginPercent: raw.margin_percent,
    incomplete: raw.incomplete,
    incompleteReasons: raw.incomplete_reasons ?? [],
  };
}

/** Tolerant of a missing/null budget key — older backends omit the block entirely. */
function toBudgetVsActual(
  raw: BudgetVsActualApiResponse | null | undefined
): BudgetVsActual | null {
  if (raw == null || typeof raw !== "object") return null;
  return {
    budgetId: raw.budget_id,
    total: raw.total,
    spent: raw.spent,
    remaining: raw.remaining,
    percentUsed: raw.percent_used,
  };
}

function mapCostBreakdown(raw: CostBreakdownApiResponse): CostBreakdown {
  return {
    categories: raw.categories.map(mapCategoryTotal),
    labor: mapLaborSummary(raw.labor),
    laborTrackedAtJobLevel: raw.labor_tracked_at_job_level,
    grandTotal: raw.grand_total,
    margin: mapMarginSummary(raw.margin),
    budget: toBudgetVsActual(raw.budget),
  };
}

// --- Cost entries ---

export async function fetchCostEntriesForJob(jobId: string): Promise<CostEntry[]> {
  const raw = await apiGet<CostEntryApiResponse[]>(
    `/api/v1/cost-entries/?job_id=${encodeURIComponent(jobId)}`
  );
  return raw.map(mapCostEntry);
}

export async function fetchCostEntriesForTradeScope(
  tradeScopeId: string
): Promise<CostEntry[]> {
  const raw = await apiGet<CostEntryApiResponse[]>(
    `/api/v1/cost-entries/?trade_scope_id=${encodeURIComponent(tradeScopeId)}`
  );
  return raw.map(mapCostEntry);
}

export async function fetchProjectCostRollup(
  projectId: string
): Promise<ProjectCostRollup> {
  const raw = await apiGet<ProjectCostRollupApiResponse>(
    `/api/v1/projects/${projectId}/cost-entries`
  );
  return {
    projectId: raw.project_id,
    total: raw.total,
    entries: raw.entries.map(mapCostEntry),
    categories: (raw.categories ?? []).map(mapCategoryTotal),
    labor: mapLaborSummary(raw.labor),
    grandTotal: raw.grand_total ?? null,
    margin: mapMarginSummary(raw.margin),
    budget: toBudgetVsActual(raw.budget),
  };
}

// --- Cost breakdowns (derived category + labor totals) ---

export async function fetchJobCostBreakdown(jobId: string): Promise<CostBreakdown> {
  const raw = await apiGet<CostBreakdownApiResponse>(
    `/api/v1/jobs/${jobId}/cost-breakdown`
  );
  return mapCostBreakdown(raw);
}

export async function fetchTradeScopeCostBreakdown(
  tradeScopeId: string
): Promise<CostBreakdown> {
  const raw = await apiGet<CostBreakdownApiResponse>(
    `/api/v1/trade-scopes/${tradeScopeId}/cost-breakdown`
  );
  return mapCostBreakdown(raw);
}

export async function fetchCostCategories(): Promise<CostCategory[]> {
  const raw = await apiGet<CostCategoryApiResponse[]>("/api/v1/cost-categories/");
  return raw.map(mapCostCategory);
}

export async function createCostEntry(input: CostEntryInput): Promise<CostEntry> {
  const raw = await apiPost<CostEntryApiResponse>("/api/v1/cost-entries/", {
    job_id: input.jobId,
    trade_scope_id: input.tradeScopeId,
    category_id: input.categoryId,
    amount: input.amount,
    incurred_date: input.incurredDate,
    vendor: input.vendor,
    note: input.note,
  });
  return mapCostEntry(raw);
}

export async function updateCostEntry(
  id: string,
  patch: CostEntryPatch
): Promise<CostEntry> {
  const raw = await apiPatch<CostEntryApiResponse>(`/api/v1/cost-entries/${id}`, {
    category_id: patch.categoryId,
    amount: patch.amount,
    incurred_date: patch.incurredDate,
    vendor: patch.vendor,
    note: patch.note,
  });
  return mapCostEntry(raw);
}

export function deleteCostEntry(id: string): Promise<void> {
  return apiDelete<void>(`/api/v1/cost-entries/${id}`);
}

// --- Receipts ---

export async function uploadCostReceipt(
  costEntryId: string,
  file: File
): Promise<CostReceipt> {
  const form = new FormData();
  form.append("file", file);
  const raw = await apiUpload<CostReceiptApiResponse>(
    `/api/v1/cost-entries/${costEntryId}/receipts`,
    form
  );
  return mapCostReceipt(raw);
}

export async function fetchReceipts(costEntryId: string): Promise<CostReceipt[]> {
  const raw = await apiGet<CostReceiptApiResponse[]>(
    `/api/v1/cost-entries/${costEntryId}/receipts`
  );
  return raw.map(mapCostReceipt);
}

// --- Budgets ---

export interface BudgetAnchorInput {
  /** Exactly one of projectId / tradeScopeId is set — the budget's anchor. */
  projectId?: string;
  tradeScopeId?: string;
  total: string;
}

/** Callers only need success/failure — the refreshed rows come from the
 *  breakdown/rollup queries, so no response mapping is done here. */
export async function setBudget(input: BudgetAnchorInput): Promise<void> {
  await apiPost<unknown>("/api/v1/budgets/", {
    project_id: input.projectId,
    trade_scope_id: input.tradeScopeId,
    total: input.total,
  });
}

export async function updateBudget(budgetId: string, total: string): Promise<void> {
  await apiPatch<unknown>(`/api/v1/budgets/${budgetId}`, { total });
}

export function deleteBudget(budgetId: string): Promise<void> {
  return apiDelete<void>(`/api/v1/budgets/${budgetId}`);
}

// --- Labor rates (append-only — no update, no delete) ---

interface LaborRateApiResponse {
  id: string;
  user_id: string;
  hourly_cost: string;
  effective_from: string;
  created_at: string;
  updated_at: string;
}

function mapLaborRate(raw: LaborRateApiResponse): LaborRate {
  return {
    id: raw.id,
    userId: raw.user_id,
    hourlyCost: raw.hourly_cost,
    effectiveFrom: raw.effective_from,
    createdAt: raw.created_at,
    updatedAt: raw.updated_at,
  };
}

/** Full append-only history for one worker (effective_from DESC, created_at DESC). */
export async function fetchLaborRateHistory(userId: string): Promise<LaborRate[]> {
  const raw = await apiGet<LaborRateApiResponse[]>(
    `/api/v1/labor-rates/?user_id=${encodeURIComponent(userId)}`
  );
  return raw.map(mapLaborRate);
}

/** One currently-effective rate per worker, in a single request (no per-row fetches). */
export async function fetchCurrentLaborRates(): Promise<LaborRate[]> {
  const raw = await apiGet<LaborRateApiResponse[]>("/api/v1/labor-rates/");
  return raw.map(mapLaborRate);
}

export async function createLaborRate(input: LaborRateInput): Promise<LaborRate> {
  const raw = await apiPost<LaborRateApiResponse>("/api/v1/labor-rates/", {
    user_id: input.userId,
    hourly_cost: input.hourlyCost,
    effective_from: input.effectiveFrom,
  });
  return mapLaborRate(raw);
}

// --- Financial dashboard (company rollup, project drill-down, margin trend) ---

interface PortfolioTotalsApiResponse {
  cost: string;
  quoted_revenue: string | null;
  incomplete_project_count: number;
  margin: MarginSummaryApiResponse;
}

interface ProjectFinancialsRowApiResponse {
  project_id: string;
  name: string;
  status: string;
  cost: string;
  margin: MarginSummaryApiResponse;
  budget?: BudgetVsActualApiResponse | null;
}

interface AttentionRowApiResponse {
  project_id: string;
  project_name: string;
  project_status: string;
  tier: string;
  anchor_label: string;
  spent: string | null;
  budget_total: string | null;
  percent_used: string | null;
}

interface CompanyFinancialsApiResponse {
  portfolio: PortfolioTotalsApiResponse;
  projects: ProjectFinancialsRowApiResponse[];
  attention: AttentionRowApiResponse[];
}

interface ScopeBudgetRowApiResponse {
  trade_scope_id: string;
  trade_name: string;
  spent: string;
  budget?: BudgetVsActualApiResponse | null;
}

interface ProjectFinancialsApiResponse {
  project_id: string;
  name: string;
  status: string;
  breakdown: CostBreakdownApiResponse;
  scopes: ScopeBudgetRowApiResponse[];
}

interface TrendBucketApiResponse {
  month: string;
  cost: string;
  margin: MarginSummaryApiResponse;
}

interface MarginTrendApiResponse {
  project_id: string;
  window: string;
  buckets: TrendBucketApiResponse[];
}

const ATTENTION_TIERS: readonly AttentionTier[] = ["overrun", "warning", "incomplete"];

/** Validates an enum-ish wire value instead of casting it — a bad payload must
 *  fail loudly at the boundary rather than surface as an impossible UI state. */
function toKnownValue<T extends string>(
  raw: string,
  allowed: readonly T[],
  label: string
): T {
  const match = allowed.find((value) => value === raw);
  if (!match) {
    throw new Error(`Malformed financials response: unknown ${label} "${raw}"`);
  }
  return match;
}

/** Every dashboard block carries a margin, so a missing one is a malformed
 *  payload — not the legitimate "no margin computed" null the shipped mapper
 *  returns for older breakdown responses. */
function requireMarginSummary(
  raw: MarginSummaryApiResponse | null | undefined,
  context: string
): MarginSummary {
  const margin = mapMarginSummary(raw);
  if (!margin) {
    throw new Error(`Malformed financials response: missing margin block for ${context}`);
  }
  return margin;
}

function mapPortfolioTotals(raw: PortfolioTotalsApiResponse): PortfolioTotals {
  return {
    cost: raw.cost,
    quotedRevenue: raw.quoted_revenue ?? null,
    incompleteProjectCount: raw.incomplete_project_count,
    margin: requireMarginSummary(raw.margin, "the portfolio"),
  };
}

function mapProjectFinancialsRow(
  raw: ProjectFinancialsRowApiResponse
): ProjectFinancialsRow {
  return {
    projectId: raw.project_id,
    name: raw.name,
    status: raw.status,
    cost: raw.cost,
    margin: requireMarginSummary(raw.margin, `project ${raw.project_id}`),
    budget: toBudgetVsActual(raw.budget),
  };
}

function mapAttentionRow(raw: AttentionRowApiResponse): AttentionRow {
  return {
    projectId: raw.project_id,
    projectName: raw.project_name,
    projectStatus: raw.project_status,
    tier: toKnownValue(raw.tier, ATTENTION_TIERS, "attention tier"),
    anchorLabel: raw.anchor_label,
    spent: raw.spent ?? null,
    budgetTotal: raw.budget_total ?? null,
    percentUsed: raw.percent_used ?? null,
  };
}

function mapCompanyFinancials(raw: CompanyFinancialsApiResponse): CompanyFinancials {
  return {
    portfolio: mapPortfolioTotals(raw.portfolio),
    projects: raw.projects.map(mapProjectFinancialsRow),
    attention: raw.attention.map(mapAttentionRow),
  };
}

function mapScopeBudgetRow(raw: ScopeBudgetRowApiResponse): ScopeBudgetRow {
  return {
    tradeScopeId: raw.trade_scope_id,
    tradeName: raw.trade_name,
    spent: raw.spent,
    budget: toBudgetVsActual(raw.budget),
  };
}

function mapProjectFinancials(raw: ProjectFinancialsApiResponse): ProjectFinancials {
  return {
    projectId: raw.project_id,
    name: raw.name,
    status: raw.status,
    breakdown: mapCostBreakdown(raw.breakdown),
    scopes: raw.scopes.map(mapScopeBudgetRow),
  };
}

function mapTrendBucket(raw: TrendBucketApiResponse): TrendBucket {
  return {
    month: raw.month,
    cost: raw.cost,
    margin: requireMarginSummary(raw.margin, `bucket ${raw.month}`),
  };
}

function mapMarginTrend(raw: MarginTrendApiResponse): MarginTrend {
  return {
    projectId: raw.project_id,
    window: toKnownValue(raw.window, TREND_WINDOWS, "trend window"),
    buckets: raw.buckets.map(mapTrendBucket),
  };
}

const COMPANY_FINANCIALS_PATH = "/api/v1/financials/company";

const projectFinancialsPath = (projectId: string) =>
  `/api/v1/projects/${encodeURIComponent(projectId)}/financials`;

export async function fetchCompanyFinancials(): Promise<CompanyFinancials> {
  const raw = await apiGet<CompanyFinancialsApiResponse>(COMPANY_FINANCIALS_PATH);
  return mapCompanyFinancials(raw);
}

export async function fetchProjectFinancials(
  projectId: string
): Promise<ProjectFinancials> {
  const raw = await apiGet<ProjectFinancialsApiResponse>(
    projectFinancialsPath(projectId)
  );
  return mapProjectFinancials(raw);
}

/** The window slices which monthly buckets come back — never which records
 *  they aggregate, so a month shared by two windows carries identical values. */
export async function fetchProjectMarginTrend(
  projectId: string,
  window: TrendWindow
): Promise<MarginTrend> {
  const raw = await apiGet<MarginTrendApiResponse>(
    `${projectFinancialsPath(projectId)}/trend?window=${window}`
  );
  return mapMarginTrend(raw);
}

interface ProfitabilityFindingApiResponse {
  id: string;
  project_id: string;
  severity: FindingSeverity;
  narrative: string;
  corrective_action: string;
  revenue_basis: RevenueBasis;
  labor_included: boolean;
  found_on: string;
  last_confirmed_on: string;
}

function mapProfitabilityFinding(
  raw: ProfitabilityFindingApiResponse
): ProfitabilityFinding {
  return {
    id: raw.id,
    projectId: raw.project_id,
    severity: raw.severity,
    narrative: raw.narrative,
    correctiveAction: raw.corrective_action,
    revenueBasis: raw.revenue_basis,
    laborIncluded: raw.labor_included,
    foundOn: raw.found_on,
    lastConfirmedOn: raw.last_confirmed_on,
  };
}

/** null = no open finding. A findings outage is its own failure surface — this
 *  never folds into fetchProjectFinancials (the 35-10 two-keys rule). */
export async function fetchProjectProfitabilityFinding(
  projectId: string
): Promise<ProfitabilityFinding | null> {
  const raw = await apiGet<ProfitabilityFindingApiResponse | null>(
    `${projectFinancialsPath(projectId)}/finding`
  );
  return raw ? mapProfitabilityFinding(raw) : null;
}
