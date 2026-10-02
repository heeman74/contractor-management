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

/**
 * Carries the browser's address to the API.
 *
 * Every browser request reaches the API through this app, so without it the API
 * sees one caller for the whole world: `5/minute` on login became five logins a
 * minute across all users, not per user, and anyone testing hit 429s that had
 * nothing to do with them.
 *
 * Deliberately not X-Forwarded-For. The platform sets that on its own hop, and
 * which entry of the resulting chain uvicorn treats as the client varies by
 * version — a header nothing else writes has one unambiguous meaning.
 *
 * It is a throttling key, not an identity. The API is publicly reachable, so a
 * caller that skips this app can set it to anything; what stands between an
 * attacker and an account is the password hashing and refresh-token reuse
 * detection, not this.
 */
export const CLIENT_IP_HEADER = "x-client-ip";

/**
 * The browser's address, from the hop between it and this app.
 *
 * Returns null when it cannot be determined, so the caller omits the header and
 * the API falls back to the connecting address rather than keying every request
 * on the word "unknown".
 */
export function clientIpOf(request: Request): string | null {
  // The platform's proxy writes the browser first in the chain.
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first;
  }
  return request.headers.get("x-real-ip");
}

/**
 * The error body to return for an upstream failure.
 *
 * An upstream error whose body is not JSON did not come from the API — it is
 * something between here and there answering on its behalf, and replacing it
 * with a generic message of our own hides that completely. A 429 from the
 * platform throttling this app's calls to the API arrived at the browser as
 * "Login failed", which reads as a credential problem and is nothing of the
 * kind; it cost hours of looking in the wrong place.
 */
export async function upstreamErrorBody(
  response: Response,
  fallbackDetail: string
): Promise<{ detail: string }> {
  try {
    const parsed = await response.json();
    if (parsed && typeof parsed.detail === "string") return { detail: parsed.detail };
  } catch {
    // Not JSON, so not the API's own answer — say so below.
  }
  return {
    detail:
      `${fallbackDetail} The service answered ${response.status} without a ` +
      "message, which means the request did not reach the application — it was " +
      "stopped between this app and the API.",
  };
}

/** Headers identifying the browser, for a request this app makes on its behalf. */
export function clientIpHeaders(request: Request): Record<string, string> {
  const ip = clientIpOf(request);
  return ip === null ? {} : { [CLIENT_IP_HEADER]: ip };
}

export const UPSTREAM_UNREACHABLE_DETAIL =
  "The service is starting up. Please try again in a moment.";

// A 429 the API did not write. Everything it sends is JSON, so a refusal
// without a JSON body came from the platform in front of it — which sees one
// address posting every user's login and reads that as credential stuffing.
// Free web services cannot receive private-network requests, so this hop has to
// cross the public edge and the throttle cannot be designed away.
//
// Waiting and trying once more gets a person in during a brief throttle. Only
// once, and only for a refusal that is not ours: retrying our own rate limit
// would be arguing with a decision the API already made.
// Measured: these bursts clear within seconds — a login refused three times in
// a row answered normally moments later. Two waits spanning that is the
// difference between a person getting in and being told to try again.
const PLATFORM_THROTTLE_WAITS_MS = [1_500, 4_000];

// Honoured when the refusal names one, but only within reach of the waits
// above: a person is holding a login form, not a background job.
const MAX_HONOURED_RETRY_AFTER_MS = 10_000;

function throttleWaitMs(response: Response, attempt: number): number {
  const header = response.headers.get("retry-after");
  const seconds = header === null ? NaN : Number(header);
  if (Number.isFinite(seconds) && seconds > 0) {
    const asMs = seconds * 1_000;
    if (asMs <= MAX_HONOURED_RETRY_AFTER_MS) return asMs;
  }
  return PLATFORM_THROTTLE_WAITS_MS[attempt] ?? 0;
}

function isPlatformThrottle(response: Response): boolean {
  if (response.status !== 429) return false;
  return !(response.headers.get("content-type") ?? "").includes("json");
}

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
  // Two failure counters, because the two failures cost different amounts. An
  // attempt that never lands has already spent the full timeout, so a second is
  // all the budget allows; a throttled one came back immediately and can afford
  // to wait and ask again.
  let failures = 0;
  let throttles = 0;

  while (true) {
    try {
      const response = await fetchFollowingRedirects(url, init);
      if (isPlatformThrottle(response) && throttles < PLATFORM_THROTTLE_WAITS_MS.length) {
        await new Promise((resolve) =>
          setTimeout(resolve, throttleWaitMs(response, throttles))
        );
        throttles += 1;
        continue;
      }
      return response;
    } catch {
      // A body that is a stream could not be re-sent, but every caller here
      // passes a string or FormData, both of which can.
      failures += 1;
      if (failures >= 2) return null;
    }
  }
}
