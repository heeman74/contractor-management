/**
 * @jest-environment node
 */
/**
 * Login must survive a cold backend without retrying a real rejection.
 *
 * The distinction is the whole point: a 502 means nothing answered and is worth
 * another attempt; a 401 is an answer about the credentials and retrying it
 * would burn the rate limiter while telling the user nothing new.
 */
import {
  LOGIN_MAX_ATTEMPTS,
  LOGIN_RETRY_DELAY_MS,
  submitLogin,
} from "../submitLogin";

const CREDENTIALS = { email: "a@example.com", password: "secret" };
const noSleep = () => Promise.resolve();
const originalFetch = global.fetch;

afterEach(() => {
  global.fetch = originalFetch;
});

it("returns a successful response on the first attempt", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response("{}", { status: 200 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await submitLogin(CREDENTIALS, { sleep: noSleep });

  expect(res.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

it("retries a 502 and returns the eventual success — the cold-start case", async () => {
  const fetchMock = jest
    .fn()
    .mockResolvedValueOnce(new Response("", { status: 502 }))
    .mockResolvedValueOnce(new Response("{}", { status: 200 }));
  global.fetch = fetchMock as unknown as typeof fetch;
  const onRetry = jest.fn();

  const res = await submitLogin(CREDENTIALS, { sleep: noSleep, onRetry });

  expect(res.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(2);
  expect(onRetry).toHaveBeenCalledWith(2);
});

it.each([401, 422])("does NOT retry a %i — that is an answer", async (status) => {
  const fetchMock = jest.fn().mockResolvedValue(new Response("", { status }));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await submitLogin(CREDENTIALS, { sleep: noSleep });

  expect(res.status).toBe(status);
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

it("retries a thrown request too", async () => {
  const fetchMock = jest
    .fn()
    .mockRejectedValueOnce(new Error("network down"))
    .mockResolvedValueOnce(new Response("{}", { status: 200 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await submitLogin(CREDENTIALS, { sleep: noSleep });

  expect(res.status).toBe(200);
});

it("gives up after the attempt limit and throws", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response("", { status: 503 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  await expect(submitLogin(CREDENTIALS, { sleep: noSleep })).rejects.toThrow();
  expect(fetchMock).toHaveBeenCalledTimes(LOGIN_MAX_ATTEMPTS);
});

it("waits between attempts rather than hammering", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response("", { status: 502 }));
  global.fetch = fetchMock as unknown as typeof fetch;
  const sleep = jest.fn().mockResolvedValue(undefined);

  await expect(submitLogin(CREDENTIALS, { sleep })).rejects.toThrow();

  expect(sleep).toHaveBeenCalledTimes(LOGIN_MAX_ATTEMPTS - 1);
  expect(sleep).toHaveBeenCalledWith(LOGIN_RETRY_DELAY_MS);
});

it("does not sleep before the first attempt", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response("{}", { status: 200 }));
  global.fetch = fetchMock as unknown as typeof fetch;
  const sleep = jest.fn().mockResolvedValue(undefined);

  await submitLogin(CREDENTIALS, { sleep });

  expect(sleep).not.toHaveBeenCalled();
});
