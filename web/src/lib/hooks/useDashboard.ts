"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiGet, apiPost } from "@/lib/api-client";
import type {
  ProjectStatusCardData,
  DashboardAlert,
  TradeTimelineData,
  TradeTaskDetail,
} from "@/lib/types/dashboard";

// --- Constants ---

const PROJECT_POLL_INTERVAL_MS = 60_000;
const ALERT_POLL_INTERVAL_MS = 30_000;
const PROJECT_STALE_TIME_MS = 30_000;
const ALERT_STALE_TIME_MS = 15_000;
const MAX_PROJECTS = 50;
const MAX_ALERTS = 30;

// --- Query hooks ---

/**
 * Fetch all active project status cards for the monitoring overview.
 * Polls every 60 seconds. Limited to 50 projects.
 */
export function useDashboardProjects() {
  return useQuery<ProjectStatusCardData[]>({
    queryKey: ["dashboard-projects"],
    queryFn: () => apiGet<ProjectStatusCardData[]>(`/api/dashboard?limit=${MAX_PROJECTS}`),
    refetchInterval: PROJECT_POLL_INTERVAL_MS,
    refetchIntervalInBackground: false,
    staleTime: PROJECT_STALE_TIME_MS,
  });
}

/**
 * Fetch AI alerts, optionally filtered by project.
 * Polls every 30 seconds for near-real-time alert visibility.
 * Limited to 30 alerts, unread first.
 */
export function useDashboardAlerts(projectId?: string) {
  const params = new URLSearchParams({ limit: String(MAX_ALERTS), unread_first: "true" });
  if (projectId) params.set("project_id", projectId);
  const url = `/api/dashboard/alerts?${params.toString()}`;

  return useQuery<DashboardAlert[]>({
    queryKey: ["dashboard-alerts", projectId],
    queryFn: () => apiGet<DashboardAlert[]>(url),
    refetchInterval: ALERT_POLL_INTERVAL_MS,
    refetchIntervalInBackground: false,
    staleTime: ALERT_STALE_TIME_MS,
  });
}

/**
 * Fetch the Gantt timeline data for a specific project.
 * Only enabled when projectId is truthy.
 */
export function useTradeTimeline(projectId: string) {
  return useQuery<TradeTimelineData>({
    queryKey: ["dashboard-timeline", projectId],
    queryFn: () =>
      apiGet<TradeTimelineData>(
        `/api/dashboard/projects/${encodeURIComponent(projectId)}/timeline`
      ),
    enabled: Boolean(projectId),
  });
}

/**
 * Fetch task detail for a specific trade scope within a project.
 * Only enabled when both IDs are truthy.
 */
export function useTradeTasks(projectId: string, tradeScopeId: string) {
  return useQuery<TradeTaskDetail[]>({
    queryKey: ["dashboard-tasks", projectId, tradeScopeId],
    queryFn: () =>
      apiGet<TradeTaskDetail[]>(
        `/api/dashboard/projects/${encodeURIComponent(projectId)}/trades/${encodeURIComponent(tradeScopeId)}/tasks`
      ),
    enabled: Boolean(projectId) && Boolean(tradeScopeId),
  });
}

// --- Mutation hooks ---

/**
 * Mark an alert as read. Uses optimistic update to immediately reflect in UI.
 */
export function useMarkAlertRead() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (alertId: string) =>
      apiPost<void>(`/api/dashboard/alerts/${encodeURIComponent(alertId)}/read`, {}),
    onMutate: async (alertId: string) => {
      // Cancel outgoing refetches so they don't overwrite our optimistic update
      await queryClient.cancelQueries({ queryKey: ["dashboard-alerts"] });

      // Snapshot previous value
      const previousAlerts = queryClient.getQueriesData<DashboardAlert[]>({
        queryKey: ["dashboard-alerts"],
      });

      // Optimistically mark as read
      queryClient.setQueriesData<DashboardAlert[]>(
        { queryKey: ["dashboard-alerts"] },
        (old) =>
          old?.map((alert) => (alert.id === alertId ? { ...alert, is_read: true } : alert))
      );

      return { previousAlerts };
    },
    onError: (_err, _alertId, context) => {
      // Rollback on error
      if (context?.previousAlerts) {
        for (const [queryKey, data] of context.previousAlerts) {
          queryClient.setQueryData(queryKey, data);
        }
      }
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["dashboard-alerts"] });
    },
  });
}

/**
 * Accept an AI rescheduling suggestion.
 * Invalidates both alerts and projects (schedule changes affect project status).
 */
export function useAcceptRescheduling() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (alertId: string) =>
      apiPost<void>(`/api/dashboard/alerts/${encodeURIComponent(alertId)}/accept`, {}),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["dashboard-alerts"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard-projects"] });
    },
  });
}

/**
 * Dismiss an AI alert. Invalidates alert cache.
 */
export function useDismissAlert() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (alertId: string) =>
      apiPost<void>(`/api/dashboard/alerts/${encodeURIComponent(alertId)}/dismiss`, {}),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["dashboard-alerts"] });
    },
  });
}
