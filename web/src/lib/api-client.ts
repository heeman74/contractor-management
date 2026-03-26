"use client";

/**
 * Client-side API fetch wrapper.
 *
 * Routes all requests through /api/proxy (which reads the httpOnly access_token cookie
 * server-side and forwards it as a Bearer header to FastAPI). Tokens are never exposed
 * to client JavaScript.
 *
 * On 401: automatically calls /api/auth/refresh once. If refresh succeeds, retries the
 * original request. If refresh fails, redirects to /login.
 */

import { tracedFetch } from "@/lib/api/withTracing";
import { logger } from "@/lib/logger";

const TAG = "ApiClient";

// Singleton refresh promise to prevent concurrent refresh requests
let refreshPromise: Promise<boolean> | null = null;

async function ensureRefreshed(): Promise<boolean> {
  if (!refreshPromise) {
    refreshPromise = fetch("/api/auth/refresh", { method: "POST" })
      .then((resp) => resp.ok)
      .finally(() => {
        refreshPromise = null;
      });
  }
  return refreshPromise;
}

export class ApiError extends Error {
  status: number;
  detail: string;

  constructor(status: number, detail: string) {
    super(detail);
    this.name = "ApiError";
    this.status = status;
    this.detail = detail;
  }
}

export async function apiClient<T>(
  path: string,
  init?: RequestInit,
  retry = true
): Promise<T> {
  const proxyUrl = `/api/proxy?path=${encodeURIComponent(path)}`;

  const resp = await tracedFetch(proxyUrl, init);

  if (resp.status === 401 && retry) {
    // Attempt token refresh (coalesced across concurrent 401s)
    logger.info(TAG, "401 received, attempting token refresh", { path });
    const refreshed = await ensureRefreshed();

    if (refreshed) {
      // Retry original request once (no further retries)
      return apiClient<T>(path, init, false);
    } else {
      // Refresh failed — redirect to login
      logger.warn(TAG, "Token refresh failed, redirecting to login", { path });
      window.location.href = "/login?reason=session_expired";
      throw new ApiError(401, "Session expired");
    }
  }

  if (!resp.ok) {
    let detail = "An unexpected error occurred";
    try {
      const errorBody = await resp.json();
      if (typeof errorBody?.detail === "string") {
        detail = errorBody.detail;
      }
    } catch {
      // Non-JSON error body — use default message
    }
    throw new ApiError(resp.status, detail);
  }

  return resp.json() as Promise<T>;
}

// Convenience methods

export function apiGet<T>(path: string): Promise<T> {
  return apiClient<T>(path, { method: "GET" });
}

export function apiPost<T>(path: string, body: unknown): Promise<T> {
  return apiClient<T>(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

export function apiPatch<T>(path: string, body: unknown): Promise<T> {
  return apiClient<T>(path, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

export function apiPut<T>(path: string, body: unknown): Promise<T> {
  return apiClient<T>(path, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

export function apiDelete<T>(path: string): Promise<T> {
  return apiClient<T>(path, { method: "DELETE" });
}

/**
 * Raw fetch through the proxy — returns the Response object directly.
 * Use for binary downloads (PDF) where resp.json() would fail.
 * Handles 401 refresh retry like apiClient.
 */
export async function apiFetchRaw(
  path: string,
  init?: RequestInit,
  retry = true
): Promise<Response> {
  const proxyUrl = `/api/proxy?path=${encodeURIComponent(path)}`;
  const resp = await tracedFetch(proxyUrl, init);

  if (resp.status === 401 && retry) {
    logger.info(TAG, "401 received on raw fetch, attempting token refresh", { path });
    const refreshed = await ensureRefreshed();
    if (refreshed) {
      return apiFetchRaw(path, init, false);
    } else {
      logger.warn(TAG, "Token refresh failed on raw fetch, redirecting to login", { path });
      window.location.href = "/login?reason=session_expired";
      throw new ApiError(401, "Session expired");
    }
  }

  if (!resp.ok) {
    let detail = "An unexpected error occurred";
    try {
      const errorBody = await resp.json();
      if (typeof errorBody?.detail === "string") {
        detail = errorBody.detail;
      }
    } catch {
      // Non-JSON error body
    }
    throw new ApiError(resp.status, detail);
  }

  return resp;
}
