"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiGet, apiPost, apiDelete } from "@/lib/api-client";
import type {
  ProjectAssignment,
  ProjectStatusUpdate,
  CreateStatusUpdatePayload,
  AssignForemanPayload,
} from "@/lib/types/foreman";

// --- Constants ---

const ASSIGNMENTS_POLL_INTERVAL_MS = 60_000;
const STATUS_POLL_INTERVAL_MS = 30_000;
const ASSIGNMENTS_STALE_TIME_MS = 30_000;
const STATUS_STALE_TIME_MS = 15_000;

// --- Query hooks ---

/**
 * Fetch projects assigned to the current foreman.
 * Polls every 60 seconds.
 */
export function useAssignedProjects() {
  return useQuery<ProjectAssignment[]>({
    queryKey: ["foreman-assignments-me"],
    queryFn: () => apiGet<ProjectAssignment[]>("/api/v1/foreman/assignments/me"),
    refetchInterval: ASSIGNMENTS_POLL_INTERVAL_MS,
    refetchIntervalInBackground: false,
    staleTime: ASSIGNMENTS_STALE_TIME_MS,
  });
}

/**
 * Fetch all foreman assignments for a specific project.
 * Only enabled when projectId is truthy.
 */
export function useProjectAssignments(projectId: string) {
  return useQuery<ProjectAssignment[]>({
    queryKey: ["foreman-assignments-project", projectId],
    queryFn: () =>
      apiGet<ProjectAssignment[]>(
        `/api/v1/foreman/assignments/project/${encodeURIComponent(projectId)}`
      ),
    enabled: Boolean(projectId),
    staleTime: ASSIGNMENTS_STALE_TIME_MS,
  });
}

/**
 * Fetch status update history for a project.
 * Polls every 30 seconds.
 */
export function useStatusUpdates(projectId: string) {
  return useQuery<ProjectStatusUpdate[]>({
    queryKey: ["foreman-status-updates", projectId],
    queryFn: () =>
      apiGet<ProjectStatusUpdate[]>(
        `/api/v1/foreman/status-updates/${encodeURIComponent(projectId)}`
      ),
    enabled: Boolean(projectId),
    refetchInterval: STATUS_POLL_INTERVAL_MS,
    refetchIntervalInBackground: false,
    staleTime: STATUS_STALE_TIME_MS,
  });
}

/**
 * Fetch only the latest status update for a project.
 * Only enabled when projectId is truthy.
 */
export function useLatestStatus(projectId: string) {
  return useQuery<ProjectStatusUpdate | null>({
    queryKey: ["foreman-status-latest", projectId],
    queryFn: () =>
      apiGet<ProjectStatusUpdate | null>(
        `/api/v1/foreman/status-updates/${encodeURIComponent(projectId)}/latest`
      ),
    enabled: Boolean(projectId),
    staleTime: STATUS_STALE_TIME_MS,
  });
}

// --- Mutation hooks ---

/**
 * Create a new daily status update for a project.
 * Invalidates status update and latest status caches on success.
 */
export function useCreateStatusUpdate() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: CreateStatusUpdatePayload) =>
      apiPost<ProjectStatusUpdate>("/api/v1/foreman/status-updates", payload),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({
        queryKey: ["foreman-status-updates", variables.project_id],
      });
      queryClient.invalidateQueries({
        queryKey: ["foreman-status-latest", variables.project_id],
      });
    },
  });
}

/**
 * Assign a foreman to a project (admin-only).
 * Invalidates project assignment caches on success.
 */
export function useAssignForeman() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: AssignForemanPayload) =>
      apiPost<ProjectAssignment>("/api/v1/foreman/assignments", payload),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({
        queryKey: ["foreman-assignments-project", variables.project_id],
      });
      queryClient.invalidateQueries({
        queryKey: ["foreman-assignments-me"],
      });
    },
  });
}

/**
 * Remove a foreman assignment (admin-only).
 * Invalidates all assignment caches on success.
 */
export function useUnassignForeman() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (assignmentId: string) =>
      apiDelete<void>(
        `/api/v1/foreman/assignments/${encodeURIComponent(assignmentId)}`
      ),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["foreman-assignments-project"] });
      queryClient.invalidateQueries({ queryKey: ["foreman-assignments-me"] });
    },
  });
}
