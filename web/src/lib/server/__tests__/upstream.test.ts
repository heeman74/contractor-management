/**
 * @jest-environment node
 */
/**
 * A sleeping backend must not read as a broken one.
 *
 * The distinction that matters: a failure to get ANY response is retried,
 * because the attempt that fails is usually the one doing the waking. An HTTP
 * error response is a real answer and must pass through untouched — retrying a
 * 401 would be wrong, and masking it would be worse.
 */
import { UPSTREAM_TIMEOUT_MS, fetchUpstream } from "../upstream";

const originalFetch = global.fetch;

afterEach(() => {
  global.fetch = originalFetch;
});

it("returns the response when the first attempt succeeds", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response("ok", { status: 200 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await fetchUpstream("http://api.test/health");

  expect(res?.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

it("retries once when the first attempt never lands — the cold-start case", async () => {
  const fetchMock = jest
    .fn()
    .mockRejectedValueOnce(new Error("timeout"))
    .mockResolvedValueOnce(new Response("ok", { status: 200 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await fetchUpstream("http://api.test/health");

  expect(res?.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

it("returns null only after both attempts fail", async () => {
  const fetchMock = jest.fn().mockRejectedValue(new Error("ECONNREFUSED"));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await fetchUpstream("http://api.test/health");

  expect(res).toBeNull();
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

it("does NOT retry an HTTP error — a 401 is an answer, not a failure", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response("nope", { status: 401 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await fetchUpstream("http://api.test/login", { method: "POST" });

  expect(res?.status).toBe(401);
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

it("applies a stated timeout rather than inheriting a default", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response(null, { status: 204 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  await fetchUpstream("http://api.test/x", { method: "POST", body: "{}" });

  const init = fetchMock.mock.calls[0][1] as RequestInit;
  expect(init.signal).toBeInstanceOf(AbortSignal);
  expect(init.method).toBe("POST");
  expect(init.body).toBe("{}");
});

it("allows enough time for an observed cold start", () => {
  // The deployed API took ~62s to wake. A budget under that would reintroduce
  // the exact failure this helper exists to prevent.
  expect(UPSTREAM_TIMEOUT_MS).toBeGreaterThan(62_000);
});
