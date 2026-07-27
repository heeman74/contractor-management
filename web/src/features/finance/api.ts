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
} from "./types";

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

interface CostBreakdownApiResponse {
  categories: CategoryTotalApiResponse[];
  labor: LaborCostSummaryApiResponse | null;
  labor_tracked_at_job_level: boolean;
  grand_total: string;
}

interface ProjectCostRollupApiResponse {
  project_id: string;
  total: string;
  entries: CostEntryApiResponse[];
  categories?: CategoryTotalApiResponse[];
  labor?: LaborCostSummaryApiResponse | null;
  grand_total?: string;
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

function mapCostBreakdown(raw: CostBreakdownApiResponse): CostBreakdown {
  return {
    categories: raw.categories.map(mapCategoryTotal),
    labor: mapLaborSummary(raw.labor),
    laborTrackedAtJobLevel: raw.labor_tracked_at_job_level,
    grandTotal: raw.grand_total,
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
