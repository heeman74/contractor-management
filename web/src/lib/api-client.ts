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

import { tracedFetch, type TraceOptions } from "@/lib/api/withTracing";
import { logger } from "@/lib/logger";

export type ApiRequestOptions = TraceOptions;

// A 401 on a retryable request is the normal expired-access-token path — the
// refresh-and-retry flow below handles it — so log it quietly rather than as an
// error. A 401 on the post-refresh retry stays loud, since it's unexpected.
function traceOptionsForAttempt(
  options: ApiRequestOptions | undefined,
  retry: boolean
): TraceOptions | undefined {
  if (!retry) return options;
  const silentStatuses = [...(options?.silentStatuses ?? [])];
  if (!silentStatuses.includes(401)) silentStatuses.push(401);
  return { ...options, silentStatuses };
}

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

/**
 * True when an error is the terminal "session expired" signal thrown after a
 * 401 whose token refresh also failed. When this is true, api-client is already
 * clearing the auth cookies and redirecting to /login?reason=session_expired,
 * so callers should show a session-expired message rather than a generic error.
 */
export function isSessionExpiredError(error: unknown): boolean {
  return error instanceof ApiError && error.status === 401;
}

const SESSION_EXPIRED_MESSAGE =
  "Your session has expired. Redirecting you to the login page…";

export { SESSION_EXPIRED_MESSAGE };

export async function apiClient<T>(
  path: string,
  init?: RequestInit,
  retry = true,
  options?: ApiRequestOptions
): Promise<T> {
  const proxyUrl = `/api/proxy?path=${encodeURIComponent(path)}`;

  const resp = await tracedFetch(proxyUrl, init, traceOptionsForAttempt(options, retry));

  if (resp.status === 401 && retry) {
    // Attempt token refresh (coalesced across concurrent 401s)
    logger.info(TAG, "401 received, attempting token refresh", { path });
    const refreshed = await ensureRefreshed();

    if (refreshed) {
      // Retry original request once (no further retries)
      return apiClient<T>(path, init, false, options);
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

export function apiGet<T>(path: string, options?: ApiRequestOptions): Promise<T> {
  return apiClient<T>(path, { method: "GET" }, true, options);
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
 * Multipart upload through the proxy. Do NOT set Content-Type — the browser adds
 * the multipart boundary, and the proxy streams the FormData to FastAPI intact.
 * Handles the 401 refresh-and-retry like the JSON helpers.
 */
export function apiUpload<T>(path: string, formData: FormData): Promise<T> {
  return apiClient<T>(path, { method: "POST", body: formData });
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
  const resp = await tracedFetch(proxyUrl, init, traceOptionsForAttempt(undefined, retry));

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

/**
 * Raw fetch through the AI-chat SSE proxy (/api/ai-chat) with the same 401
 * refresh-and-retry as apiClient. Returns the raw Response (streamable body)
 * WITHOUT throwing on non-2xx — the AI chat hooks inspect the response and its
 * error body / SSE stream themselves.
 *
 * Reuses the coalesced ensureRefreshed() so that concurrent 401s trigger only
 * one refresh-token rotation (a second rotation would trip the backend's
 * refresh-token family-reuse revocation and log the user out).
 *
 * `path` is the FastAPI path (e.g. "/api/v1/ai/intake/message"); the proxy
 * query string is built here. Bodies must be strings so a retry can re-send.
 */
export async function aiChatFetch(
  path: string,
  init: RequestInit,
  retry = true
): Promise<Response> {
  const proxyUrl = `/api/ai-chat?path=${encodeURIComponent(path)}`;
  const resp = await fetch(proxyUrl, init);

  if (resp.status === 401 && retry) {
    logger.info(TAG, "401 on AI chat, attempting token refresh", { path });
    const refreshed = await ensureRefreshed();
    if (refreshed) {
      return aiChatFetch(path, init, false);
    }
    logger.warn(TAG, "Token refresh failed on AI chat, redirecting to login", {
      path,
    });
    window.location.href = "/login?reason=session_expired";
    throw new ApiError(401, "Session expired");
  }

  return resp;
}
