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
} from "./api";
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
