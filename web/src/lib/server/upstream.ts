/**
 * Upstream fetch for the route handlers that proxy to FastAPI.
 *
 * Exists because a bare `fetch` turned a sleeping backend into a login failure.
 * On a platform that idles instances, the first request after a quiet spell
 * pays the full cold start — measured at ~62s against the deployed API — while
 * the routes had no explicit timeout and no retry, so the wait died on a
 * default and every caller reported "Unable to reach authentication service".
 *
 * Two changes fix it. The timeout is stated rather than inherited, with enough
 * room for a cold start; and a failed attempt is retried once, because the
 * attempt that fails is usually the one that does the waking.
 */

export const UPSTREAM_TIMEOUT_MS = 75_000;

// Route handlers declare `export const maxDuration = 90` as a literal rather
// than importing it: Next evaluates segment config statically and rejects a
// reference, so a shared constant here would be unusable by the very routes
// that need it.

export const UPSTREAM_UNREACHABLE_DETAIL =
  "The service is starting up. Please try again in a moment.";

/**
 * Fetch an upstream URL, retrying once if the attempt never produced a
 * response. Returns null when both attempts failed, which callers report as
 * 502 — an HTTP error response is NOT a failure here and is returned as-is, so
 * a 401 stays a 401 rather than being retried or masked.
 */
export async function fetchUpstream(
  url: string,
  init: RequestInit = {}
): Promise<Response | null> {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      return await fetch(url, {
        ...init,
        signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      });
    } catch {
      // Retry once. A body that is a stream could not be re-sent, but every
      // caller here passes a string or FormData, both of which can.
      if (attempt === 1) return null;
    }
  }
  return null;
}
