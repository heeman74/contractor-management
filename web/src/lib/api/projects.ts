"use client";

import { useQuery } from "@tanstack/react-query";
import { apiGet, apiPost, apiPatch } from "@/lib/api-client";
import type {
  ProjectResponse,
  TradeCatalogResponse,
  TradeScopeResponse,
  TaskResponse,
  ContractorMatch,
  ProjectCreate,
  TradeScopeCreate,
  TaskCreate,
} from "@/types/projects";

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
