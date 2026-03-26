"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiGet, apiPost } from "@/lib/api-client";
import type {
  ProjectStatusCard,
  DashboardAlert,
  TradeTimelineData,
  TradeTaskDetail,
} from "@/lib/types/dashboard";

// --- Query hooks ---

/**
 * Fetch all active project status cards for the monitoring overview.
 * Polls every 60 seconds.
 */
export function useDashboardProjects() {
  return useQuery<ProjectStatusCard[]>({
    queryKey: ["dashboard-projects"],
    queryFn: () => apiGet<ProjectStatusCard[]>("/api/dashboard"),
    refetchInterval: 60_000,
  });
}

/**
 * Fetch AI alerts, optionally filtered by project.
 * Polls every 30 seconds for near-real-time alert visibility.
 */
export function useDashboardAlerts(projectId?: string) {
  const url = projectId
    ? `/api/dashboard/alerts?project_id=${encodeURIComponent(projectId)}`
    : "/api/dashboard/alerts";
  return useQuery<DashboardAlert[]>({
    queryKey: ["dashboard-alerts", projectId],
    queryFn: () => apiGet<DashboardAlert[]>(url),
    refetchInterval: 30_000,
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
 * Mark an alert as read. Invalidates alert cache.
 */
export function useMarkAlertRead() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (alertId: string) =>
      apiPost<void>(`/api/dashboard/alerts/${encodeURIComponent(alertId)}/read`, {}),
    onSuccess: () => {
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
