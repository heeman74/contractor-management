/**
 * Login that survives a sleeping backend.
 *
 * The API idles on the free plan and its first request pays the full cold start —
 * measured at ~61s against the deployed instance. The route handler already
 * retries with a generous timeout, but that does not help when the platform edge
 * gives up on the browser's request first: the handler is still waiting, and the
 * browser already has a 502. Only a retry on the client side survives that.
 *
 * Retries are confined to gateway failures and thrown requests. A 401 or 422 is a
 * real answer about the credentials and must be shown immediately — retrying it
 * would hammer the rate limiter and tell the user nothing.
 */

/** Statuses that mean "nothing answered", as opposed to "the answer was no". */
export const GATEWAY_STATUSES: ReadonlySet<number> = new Set([502, 503, 504]);

export const LOGIN_MAX_ATTEMPTS = 3;
export const LOGIN_RETRY_DELAY_MS = 2_000;

export interface SubmitLoginOptions {
  /** Called before each retry, so the UI can explain the wait. */
  onRetry?: (attempt: number) => void;
  /** Injected for tests; real callers use the default. */
  sleep?: (ms: number) => Promise<void>;
}

const defaultSleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export async function submitLogin(
  credentials: { email: string; password: string },
  options: SubmitLoginOptions = {}
): Promise<Response> {
  const { onRetry, sleep = defaultSleep } = options;
  let lastError: unknown;

  for (let attempt = 1; attempt <= LOGIN_MAX_ATTEMPTS; attempt += 1) {
    if (attempt > 1) {
      onRetry?.(attempt);
      await sleep(LOGIN_RETRY_DELAY_MS);
    }

    try {
      const response = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(credentials),
      });
      if (!GATEWAY_STATUSES.has(response.status)) return response;
      lastError = new Error(`gateway ${response.status}`);
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError ?? new Error("login failed");
}
