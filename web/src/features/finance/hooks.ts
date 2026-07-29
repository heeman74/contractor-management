"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchCostEntriesForJob,
  fetchCostEntriesForTradeScope,
  fetchProjectCostRollup,
  fetchJobCostBreakdown,
  fetchTradeScopeCostBreakdown,
  fetchCostCategories,
  fetchReceipts,
  fetchLaborRateHistory,
  fetchCurrentLaborRates,
  createCostEntry,
  updateCostEntry,
  deleteCostEntry,
  uploadCostReceipt,
  createLaborRate,
  setBudget,
  updateBudget,
  deleteBudget,
  fetchCompanyFinancials,
  fetchProjectFinancials,
  fetchProjectMarginTrend,
  fetchProjectProfitabilityFinding,
} from "./api";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { FINANCE_VIEW_PERMISSION, type TrendWindow } from "./types";
import type { BudgetAnchorInput } from "./api";
import type { CostEntryInput, CostEntryPatch, LaborRateInput } from "./types";

// --- Queries ---

export function useCostEntriesForJob(jobId: string) {
  return useQuery({
    queryKey: ["cost-entries", "job", jobId],
    queryFn: () => fetchCostEntriesForJob(jobId),
    enabled: !!jobId,
  });
}

export function useCostEntriesForTradeScope(tradeScopeId: string) {
  return useQuery({
    queryKey: ["cost-entries", "trade-scope", tradeScopeId],
    queryFn: () => fetchCostEntriesForTradeScope(tradeScopeId),
    enabled: !!tradeScopeId,
  });
}

export function useProjectCostRollup(projectId: string) {
  return useQuery({
    queryKey: ["cost-entries", "project-rollup", projectId],
    queryFn: () => fetchProjectCostRollup(projectId),
    enabled: !!projectId,
  });
}

/**
 * Breakdown queries live under the "cost-entries" prefix so every cost write
 * (and rate append via useAddLaborRate) refreshes them through
 * invalidateAllCostEntries.
 */
export function useJobCostBreakdown(jobId: string) {
  return useQuery({
    queryKey: ["cost-entries", "breakdown", "job", jobId],
    queryFn: () => fetchJobCostBreakdown(jobId),
    enabled: !!jobId,
  });
}

export function useTradeScopeCostBreakdown(tradeScopeId: string) {
  return useQuery({
    queryKey: ["cost-entries", "breakdown", "trade-scope", tradeScopeId],
    queryFn: () => fetchTradeScopeCostBreakdown(tradeScopeId),
    enabled: !!tradeScopeId,
  });
}

export function useCostCategories() {
  return useQuery({
    queryKey: ["cost-categories"],
    queryFn: fetchCostCategories,
  });
}

export function useReceipts(costEntryId: string) {
  return useQuery({
    queryKey: ["cost-receipts", costEntryId],
    queryFn: () => fetchReceipts(costEntryId),
    enabled: !!costEntryId,
  });
}

/**
 * Financial dashboard queries.
 *
 * Their keys sit under the "cost-entries" prefix so invalidateAllCostEntries —
 * already fired by every cost, budget and rate write — refreshes the dashboard
 * for free. The trend window is part of its own key, so switching 3m→12m
 * refetches only the trend and never the window-independent portfolio tiles.
 */

/**
 * `enabled` is the fetch-side half of the permission gate: FinanceGate stops the
 * render, this stops the request, and can() is false while permissions are still
 * loading. Together they are what guarantee zero /api/v1/financials/* traffic on
 * an unauthorized or not-yet-resolved visit. Dropping `enabled` would still look
 * correct on screen while silently weakening the SC3 zero-request test into one
 * that passes for the wrong reason.
 */
export function useCompanyFinancials() {
  const { can } = usePermissions();
  return useQuery({
    queryKey: ["cost-entries", "financials", "company"],
    queryFn: fetchCompanyFinancials,
    enabled: can(FINANCE_VIEW_PERMISSION),
  });
}

export function useProjectFinancials(projectId: string) {
  const { can } = usePermissions();
  return useQuery({
    queryKey: ["cost-entries", "financials", "project", projectId],
    queryFn: () => fetchProjectFinancials(projectId),
    enabled: can(FINANCE_VIEW_PERMISSION) && !!projectId,
  });
}

export function useProjectMarginTrend(projectId: string, window: TrendWindow) {
  const { can } = usePermissions();
  return useQuery({
    queryKey: ["cost-entries", "financials", "trend", projectId, window],
    queryFn: () => fetchProjectMarginTrend(projectId, window),
    enabled: can(FINANCE_VIEW_PERMISSION) && !!projectId,
    // Keeps the previous window's chart on screen while the new one loads.
    placeholderData: (previous) => previous,
  });
}

/**
 * `enabled` is the fetch-side half of the permission gate. FinanceGate stops the
 * render; this stops the request. Without it an unauthorized visit still issues
 * the call and the SC2 "zero finding requests" assertion would pass for the wrong
 * reason. The key sits under the shared "cost-entries" prefix so
 * invalidateAllCostEntries refreshes it for free.
 */
export function useProjectProfitabilityFinding(projectId: string) {
  const { can } = usePermissions();
  return useQuery({
    queryKey: ["cost-entries", "financials", "finding", projectId],
    queryFn: () => fetchProjectProfitabilityFinding(projectId),
    enabled: can(FINANCE_VIEW_PERMISSION) && !!projectId,
  });
}

// --- Mutations ---

/**
 * Invalidates every cost-entries query (job/trade-scope lists + project
 * rollups) after a write. Broad on purpose: a single cost entry can affect
 * a job/trade-scope list AND the project rollup it aggregates into, and we
 * don't always know the projectId at the call site.
 */
function invalidateAllCostEntries(queryClient: ReturnType<typeof useQueryClient>) {
  queryClient.invalidateQueries({ queryKey: ["cost-entries"] });
}

export function useAddCostEntry() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: CostEntryInput) => createCostEntry(input),
    onSuccess: () => invalidateAllCostEntries(queryClient),
  });
}

export function useUpdateCostEntry() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: CostEntryPatch }) =>
      updateCostEntry(id, patch),
    onSuccess: () => invalidateAllCostEntries(queryClient),
  });
}

export function useDeleteCostEntry() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => deleteCostEntry(id),
    onSuccess: () => invalidateAllCostEntries(queryClient),
  });
}

/**
 * Budget mutations invalidate the whole cost-entries prefix: the breakdown and
 * rollup queries that carry the budget block both live under it, so one
 * invalidation refreshes every budget row on screen.
 */
export function useSetBudget() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: BudgetAnchorInput) => setBudget(input),
    onSuccess: () => invalidateAllCostEntries(queryClient),
  });
}

export function useUpdateBudget() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ budgetId, total }: { budgetId: string; total: string }) =>
      updateBudget(budgetId, total),
    onSuccess: () => invalidateAllCostEntries(queryClient),
  });
}

export function useDeleteBudget() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (budgetId: string) => deleteBudget(budgetId),
    onSuccess: () => invalidateAllCostEntries(queryClient),
  });
}

export function useLaborRateHistory(userId: string, enabled = true) {
  return useQuery({
    queryKey: ["labor-rates", "history", userId],
    queryFn: () => fetchLaborRateHistory(userId),
    enabled: enabled && !!userId,
  });
}

export function useCurrentLaborRates(enabled = true) {
  return useQuery({
    queryKey: ["labor-rates", "current"],
    queryFn: fetchCurrentLaborRates,
    enabled,
  });
}

/**
 * Appending a rate moves derived labor cost in every breakdown, so this
 * invalidates the whole cost-entries prefix as well as the rate queries.
 */
export function useAddLaborRate() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: LaborRateInput) => createLaborRate(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["labor-rates"] });
      invalidateAllCostEntries(queryClient);
    },
  });
}

export function useUploadReceipt() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ costEntryId, file }: { costEntryId: string; file: File }) =>
      uploadCostReceipt(costEntryId, file),
    onSuccess: (_receipt, variables) => {
      queryClient.invalidateQueries({ queryKey: ["cost-receipts", variables.costEntryId] });
    },
  });
}
