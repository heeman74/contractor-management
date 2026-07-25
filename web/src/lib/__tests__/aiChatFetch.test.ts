import { aiChatFetch, ApiError } from "../api-client";

/**
 * Verifies the AI-chat proxy fetch participates in the same 401
 * refresh-and-retry as the rest of the app, so an expired 15-minute access
 * token mid-conversation transparently refreshes instead of hard-failing.
 */

function jsonResponse(status: number, body: unknown = {}): Response {
  return {
    status,
    ok: status >= 200 && status < 300,
    json: async () => body,
  } as unknown as Response;
}

const AI_PATH = "/api/v1/ai/intake/message";
const REFRESH_URL = "/api/auth/refresh";

afterEach(() => {
  jest.restoreAllMocks();
  (globalThis.fetch as jest.Mock | undefined)?.mockReset?.();
});

test("returns the response directly on success (no refresh attempted)", async () => {
  const fetchMock = jest.fn().mockResolvedValue(jsonResponse(200, { ok: true }));
  globalThis.fetch = fetchMock;

  const res = await aiChatFetch(AI_PATH, { method: "POST", body: "{}" });

  expect(res.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(1);
  const calledUrl = String(fetchMock.mock.calls[0][0]);
  expect(calledUrl).toContain("/api/ai-chat?path=");
  expect(calledUrl).toContain(encodeURIComponent(AI_PATH));
});

test("on 401 it refreshes once and retries, returning the retried response", async () => {
  const fetchMock = jest
    .fn()
    .mockImplementation(async (url: string | URL) => {
      const u = String(url);
      if (u.includes(REFRESH_URL)) return jsonResponse(200); // refresh succeeds
      // AI chat: 401 first, 200 on the retry
      fetchMock.aiCalls = (fetchMock.aiCalls ?? 0) + 1;
      return jsonResponse(fetchMock.aiCalls === 1 ? 401 : 200, { streamed: true });
    }) as jest.Mock & { aiCalls?: number };
  globalThis.fetch = fetchMock;

  const res = await aiChatFetch(AI_PATH, { method: "POST", body: "{}" });

  expect(res.status).toBe(200);
  // exactly one refresh call
  const refreshCalls = fetchMock.mock.calls.filter((c) =>
    String(c[0]).includes(REFRESH_URL)
  );
  expect(refreshCalls).toHaveLength(1);
  // two AI-chat attempts (original + retry)
  const aiCalls = fetchMock.mock.calls.filter((c) =>
    String(c[0]).includes("/api/ai-chat")
  );
  expect(aiCalls).toHaveLength(2);
});

test("when refresh fails it throws an ApiError (session expired)", async () => {
  // Setting window.location.href is a no-op in jsdom (logs a navigation
  // notice); the observable contract here is that it throws rather than
  // silently returning the 401.
  jest.spyOn(console, "error").mockImplementation(() => {});
  const fetchMock = jest.fn().mockImplementation(async (url: string | URL) => {
    const u = String(url);
    if (u.includes(REFRESH_URL)) return jsonResponse(401); // refresh fails
    return jsonResponse(401); // AI chat unauthorized
  });
  globalThis.fetch = fetchMock;

  await expect(
    aiChatFetch(AI_PATH, { method: "POST", body: "{}" })
  ).rejects.toBeInstanceOf(ApiError);
});

test("a non-401 error response is returned as-is (caller inspects it)", async () => {
  const fetchMock = jest.fn().mockResolvedValue(jsonResponse(500, { detail: "boom" }));
  globalThis.fetch = fetchMock;

  const res = await aiChatFetch(AI_PATH, { method: "POST", body: "{}" });

  expect(res.status).toBe(500);
  // no refresh attempted for non-401
  expect(fetchMock).toHaveBeenCalledTimes(1);
});
