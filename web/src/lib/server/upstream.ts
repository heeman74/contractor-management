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
 *
 * It also follows redirects itself, which is not the belt-and-braces it looks
 * like. Letting fetch follow them cost us every list endpoint in production:
 * FastAPI registers them with a trailing slash and 307s `/api/v1/jobs` to
 * `/api/v1/jobs/`, and because the platform terminates TLS and forwards plain
 * HTTP, that Location came back as `http://`. A https -> http hop is
 * cross-origin, where fetch silently drops Authorization — so the backend saw
 * an unauthenticated request and answered 401. Endpoints registered without a
 * trailing slash never redirected and kept working, which made it look like
 * selective auth failure rather than a redirect problem.
 */

export const UPSTREAM_TIMEOUT_MS = 75_000;

// Route handlers declare `export const maxDuration = 90` as a literal rather
// than importing it: Next evaluates segment config statically and rejects a
// reference, so a shared constant here would be unusable by the very routes
// that need it.

/**
 * Set on a response the proxy generated about the upstream, rather than one the
 * upstream produced. The platform answers 502 when this app fails to respond
 * too, so without a marker there is no way to tell which end broke.
 */
export const UPSTREAM_ERROR_HEADER = "x-upstream-error";

export const UPSTREAM_UNREACHABLE_DETAIL =
  "The service is starting up. Please try again in a moment.";

const MAX_UPSTREAM_REDIRECTS = 3;

// 307/308 keep the method and body; the older codes are followed as GET, which
// is what every client already does with them.
const BODY_PRESERVING_REDIRECTS = new Set([307, 308]);

/**
 * Resolve a Location against the URL that produced it, or null to stop.
 *
 * Refuses to follow a redirect to another host, because following it would hand
 * that host our Authorization header. For the same host, the hop is re-issued
 * on the origin we were already talking to: the scheme and port the upstream
 * puts in the Location reflect what IT received behind the TLS terminator, and
 * honouring a downgrade is exactly what loses the credentials.
 */
function resolveRedirect(current: URL, location: string): URL | null {
  let next: URL;
  try {
    next = new URL(location, current);
  } catch {
    return null;
  }
  if (next.hostname !== current.hostname) return null;

  next.protocol = current.protocol;
  next.port = current.port;
  return next;
}

/** One attempt, following same-host redirects with the headers re-attached. */
async function fetchFollowingRedirects(
  url: string,
  init: RequestInit
): Promise<Response> {
  let current = new URL(url);
  let hopInit = init;
  let response: Response | null = null;

  for (let hop = 0; hop <= MAX_UPSTREAM_REDIRECTS; hop += 1) {
    response = await fetch(current.href, {
      ...hopInit,
      // Manual, so the follow-up is ours to make with the headers intact.
      redirect: "manual",
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });

    const location = response.headers.get("location");
    if (response.status < 300 || response.status >= 400 || location === null) {
      return response;
    }

    const next = resolveRedirect(current, location);
    if (next === null) return response;

    if (!BODY_PRESERVING_REDIRECTS.has(response.status)) {
      hopInit = { ...hopInit, method: "GET", body: undefined };
    }
    current = next;
  }

  // Out of hops: hand back the last redirect rather than looping forever.
  return response as Response;
}

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
      return await fetchFollowingRedirects(url, init);
    } catch {
      // Retry once. A body that is a stream could not be re-sent, but every
      // caller here passes a string or FormData, both of which can.
      if (attempt === 1) return null;
    }
  }
  return null;
}
