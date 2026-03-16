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

  const resp = await fetch(proxyUrl, init);

  if (resp.status === 401 && retry) {
    // Attempt token refresh
    const refreshResp = await fetch("/api/auth/refresh", { method: "POST" });

    if (refreshResp.ok) {
      // Retry original request once (no further retries)
      return apiClient<T>(path, init, false);
    } else {
      // Refresh failed — redirect to login
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

export function apiDelete<T>(path: string): Promise<T> {
  return apiClient<T>(path, { method: "DELETE" });
}
