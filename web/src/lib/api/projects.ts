"use client";

import { useQuery } from "@tanstack/react-query";
import { apiGet, apiPost, apiPatch, apiDelete } from "@/lib/api-client";
import type {
  ProjectResponse,
  ProjectAssignmentResponse,
  TradeCatalogResponse,
  TradeScopeResponse,
  TaskResponse,
  ContractorMatch,
  ProjectCreate,
  TradeScopeCreate,
  TaskCreate,
} from "@/types/projects";
import type {
  TaskDependencyResponse,
  TaskDependencyCreate,
  ProjectZoneResponse,
  ProjectZoneCreate,
  ConflictRecord,
} from "@/types/dependencies";

// --- API client functions ---

export function fetchProjects(): Promise<ProjectResponse[]> {
  return apiGet<ProjectResponse[]>("/api/v1/projects/");
}

export function fetchProject(id: string): Promise<ProjectResponse> {
  return apiGet<ProjectResponse>(`/api/v1/projects/${id}`);
}

export function createProject(data: ProjectCreate): Promise<ProjectResponse> {
  return apiPost<ProjectResponse>("/api/v1/projects/", data);
}

// --- Project assignments (PM / contractor / …) ---

export function fetchProjectAssignments(
  projectId: string
): Promise<ProjectAssignmentResponse[]> {
  return apiGet<ProjectAssignmentResponse[]>(
    `/api/v1/projects/${projectId}/assignments`
  );
}

export function assignToProject(
  projectId: string,
  data: { user_id: string; role: string }
): Promise<ProjectAssignmentResponse> {
  return apiPost<ProjectAssignmentResponse>(
    `/api/v1/projects/${projectId}/assignments`,
    data
  );
}

export function unassignFromProject(
  projectId: string,
  assignmentId: string
): Promise<void> {
  return apiDelete<void>(
    `/api/v1/projects/${projectId}/assignments/${assignmentId}`
  );
}

export function useProjectAssignments(projectId: string) {
  return useQuery({
    queryKey: ["project-assignments", projectId],
    queryFn: () => fetchProjectAssignments(projectId),
    enabled: !!projectId,
  });
}

export function updateProject(
  id: string,
  data: Partial<ProjectCreate>
): Promise<ProjectResponse> {
  return apiPatch<ProjectResponse>(`/api/v1/projects/${id}`, data);
}

export function fetchTradeCatalog(): Promise<TradeCatalogResponse[]> {
  return apiGet<TradeCatalogResponse[]>("/api/v1/trade-catalog/");
}

export function createTradeCatalogEntry(data: {
  name: string;
  color?: string;
}): Promise<TradeCatalogResponse> {
  return apiPost<TradeCatalogResponse>("/api/v1/trade-catalog/", data);
}

export function fetchTradeScopes(
  projectId: string
): Promise<TradeScopeResponse[]> {
  return apiGet<TradeScopeResponse[]>(
    `/api/v1/trade-scopes/?project_id=${projectId}`
  );
}

export function createTradeScope(
  data: TradeScopeCreate
): Promise<TradeScopeResponse> {
  return apiPost<TradeScopeResponse>("/api/v1/trade-scopes/", data);
}

export function updateTradeScope(
  id: string,
  data: Partial<TradeScopeCreate>
): Promise<TradeScopeResponse> {
  return apiPatch<TradeScopeResponse>(`/api/v1/trade-scopes/${id}`, data);
}

export function fetchTasks(tradeScopeId: string): Promise<TaskResponse[]> {
  return apiGet<TaskResponse[]>(
    `/api/v1/tasks/?trade_scope_id=${tradeScopeId}`
  );
}

export function createTask(data: TaskCreate): Promise<TaskResponse> {
  return apiPost<TaskResponse>("/api/v1/tasks/", data);
}

export function fetchContractors(
  tradeCatalogId?: string
): Promise<ContractorMatch[]> {
  const qs = tradeCatalogId
    ? `?trade_catalog_id=${tradeCatalogId}`
    : "";
  return apiGet<ContractorMatch[]>(`/api/v1/contractors/${qs}`);
}

// --- TanStack Query hooks ---

export function useProjects() {
  return useQuery({
    queryKey: ["projects"],
    queryFn: fetchProjects,
  });
}

export function useProject(id: string) {
  return useQuery({
    queryKey: ["projects", id],
    queryFn: () => fetchProject(id),
    enabled: !!id,
  });
}

export function useTradeCatalog() {
  return useQuery({
    queryKey: ["trade-catalog"],
    queryFn: fetchTradeCatalog,
  });
}

export function useTradeScopes(projectId: string) {
  return useQuery({
    queryKey: ["trade-scopes", projectId],
    queryFn: () => fetchTradeScopes(projectId),
    enabled: !!projectId,
  });
}

export function useTasks(tradeScopeId: string) {
  return useQuery({
    queryKey: ["tasks", tradeScopeId],
    queryFn: () => fetchTasks(tradeScopeId),
    enabled: !!tradeScopeId,
  });
}

export function useContractors(tradeCatalogId?: string) {
  return useQuery({
    queryKey: ["contractors", tradeCatalogId ?? "all"],
    queryFn: () => fetchContractors(tradeCatalogId),
  });
}

// --- Dependencies API ---

export function fetchTaskDependencies(taskId: string): Promise<TaskDependencyResponse[]> {
  return apiGet<TaskDependencyResponse[]>(`/api/v1/tasks/${taskId}/dependencies`);
}

export function createTaskDependency(
  successorTaskId: string,
  data: TaskDependencyCreate
): Promise<TaskDependencyResponse> {
  return apiPost<TaskDependencyResponse>(
    `/api/v1/tasks/${successorTaskId}/dependencies`,
    data
  );
}

export function deleteTaskDependency(dependencyId: string): Promise<void> {
  return apiDelete<void>(`/api/v1/dependencies/${dependencyId}`);
}

// --- Zones API ---

export function fetchProjectZones(projectId: string): Promise<ProjectZoneResponse[]> {
  return apiGet<ProjectZoneResponse[]>(`/api/v1/projects/${projectId}/zones`);
}

export function createProjectZone(
  projectId: string,
  data: ProjectZoneCreate
): Promise<ProjectZoneResponse> {
  return apiPost<ProjectZoneResponse>(`/api/v1/projects/${projectId}/zones`, data);
}

export function deleteProjectZone(zoneId: string): Promise<void> {
  return apiDelete<void>(`/api/v1/zones/${zoneId}`);
}

// --- Conflicts API ---

export function fetchProjectConflicts(projectId: string): Promise<ConflictRecord[]> {
  return apiGet<ConflictRecord[]>(`/api/v1/projects/${projectId}/conflicts`);
}

// --- TanStack Query hooks for dependencies / zones / conflicts ---

export function useProjectZones(projectId: string) {
  return useQuery({
    queryKey: ["project-zones", projectId],
    queryFn: () => fetchProjectZones(projectId),
    enabled: !!projectId,
  });
}

export function useProjectConflicts(projectId: string) {
  return useQuery({
    queryKey: ["project-conflicts", projectId],
    queryFn: () => fetchProjectConflicts(projectId),
    enabled: !!projectId,
  });
}

export function useTaskDependencies(taskId: string) {
  return useQuery({
    queryKey: ["task-dependencies", taskId],
    queryFn: () => fetchTaskDependencies(taskId),
    enabled: !!taskId,
  });
}

/**
 * Fetch all dependencies for all tasks in a project by collecting unique task IDs
 * from scopes and calling fetchTaskDependencies for each, then deduplicating.
 */
export function fetchProjectDependencies(scopes: TradeScopeResponse[]): Promise<TaskDependencyResponse[]> {
  const taskIds = scopes.flatMap(s => (s.tasks ?? []).map(t => t.id));
  if (taskIds.length === 0) return Promise.resolve([]);
  return Promise.all(taskIds.map(id => fetchTaskDependencies(id)))
    .then(results => {
      const seen = new Set<string>();
      const deduped: TaskDependencyResponse[] = [];
      for (const deps of results) {
        for (const dep of deps) {
          if (!seen.has(dep.id)) {
            seen.add(dep.id);
            deduped.push(dep);
          }
        }
      }
      return deduped;
    });
}

export function useProjectDependencies(scopes: TradeScopeResponse[] | undefined) {
  const taskIds = (scopes ?? []).flatMap(s => (s.tasks ?? []).map(t => t.id)).sort().join(",");
  return useQuery({
    queryKey: ["project-dependencies", taskIds],
    queryFn: () => fetchProjectDependencies(scopes ?? []),
    enabled: !!scopes && scopes.length > 0,
  });
}
