/**
 * API tracing utilities for ContractorHub web app.
 *
 * Generates X-Request-ID headers, logs request/response timing,
 * and correlates logs via the structured logger.
 *
 * NEVER logs request or response bodies.
 */

import { logger } from "@/lib/logger";

const TAG = "ApiTrace";

/** Generate a UUID v4 using the Web Crypto API. */
function generateRequestId(): string {
  // crypto.randomUUID is available in modern browsers and Node 19+
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  // Fallback: manual v4 UUID from getRandomValues
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/**
 * Wrap a fetch call with request tracing.
 *
 * - Injects X-Request-ID header
 * - Logs request start (debug) and response (info) with duration
 * - Logs errors at error level
 * - Returns the Response as-is (does not consume the body)
 */
export async function tracedFetch(
  input: string | URL | Request,
  init?: RequestInit
): Promise<Response> {
  const requestId = generateRequestId();

  // Merge X-Request-ID into headers
  const headers = new Headers(init?.headers);
  headers.set("X-Request-ID", requestId);

  const method = init?.method ?? "GET";
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;

  logger.debug(TAG, `${method} ${url}`, { requestId });

  const start = performance.now();

  try {
    const response = await fetch(url, { ...init, headers });
    const durationMs = Math.round(performance.now() - start);

    if (response.ok) {
      logger.info(TAG, `${method} ${url} -> ${response.status}`, {
        status: response.status,
        durationMs,
        requestId,
      });
    } else {
      logger.error(TAG, `${method} ${url} -> ${response.status}`, {
        status: response.status,
        durationMs,
        requestId,
      });
    }

    return response;
  } catch (err: unknown) {
    const durationMs = Math.round(performance.now() - start);
    const errorMessage = err instanceof Error ? err.message : String(err);
    logger.error(TAG, `${method} ${url} FAILED`, {
      error: errorMessage,
      durationMs,
      requestId,
    });
    throw err;
  }
}
