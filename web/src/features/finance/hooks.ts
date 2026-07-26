"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchCostEntriesForJob,
  fetchCostEntriesForTradeScope,
  fetchProjectCostRollup,
  fetchCostCategories,
  fetchReceipts,
  createCostEntry,
  updateCostEntry,
  deleteCostEntry,
  uploadCostReceipt,
} from "./api";
import type { CostEntryInput, CostEntryPatch } from "./types";

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
