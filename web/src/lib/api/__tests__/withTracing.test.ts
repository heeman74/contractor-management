/**
 * Tests for the API tracing wrapper.
 *
 * jsdom does not provide the global Response constructor, so we create
 * mock response objects that match the shape tracedFetch expects.
 */

// Mock the logger
jest.mock("@/lib/logger", () => ({
  logger: {
    debug: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

import { tracedFetch } from "../withTracing";
import { logger } from "@/lib/logger";

const mockLogger = logger as jest.Mocked<typeof logger>;

function fakeResponse(status: number): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: new Headers(),
    json: () => Promise.resolve({}),
  } as unknown as Response;
}

afterEach(() => {
  jest.restoreAllMocks();
  jest.clearAllMocks();
});

describe("tracedFetch", () => {
  test("injects X-Request-ID header", async () => {
    const mockFetch = jest.fn().mockResolvedValue(fakeResponse(200));
    global.fetch = mockFetch;

    await tracedFetch("https://example.com/api/test", { method: "GET" });

    const calledHeaders = mockFetch.mock.calls[0][1].headers as Headers;
    expect(calledHeaders.get("X-Request-ID")).toBeTruthy();
  });

  test("logs debug on request start", async () => {
    global.fetch = jest.fn().mockResolvedValue(fakeResponse(200));

    await tracedFetch("https://example.com/api/test");

    expect(mockLogger.debug).toHaveBeenCalledWith(
      "ApiTrace",
      expect.stringContaining("GET https://example.com/api/test"),
      expect.objectContaining({ requestId: expect.any(String) })
    );
  });

  test("logs info on successful response", async () => {
    global.fetch = jest.fn().mockResolvedValue(fakeResponse(200));

    await tracedFetch("https://example.com/test");

    expect(mockLogger.info).toHaveBeenCalledWith(
      "ApiTrace",
      expect.stringContaining("200"),
      expect.objectContaining({
        status: 200,
        durationMs: expect.any(Number),
        requestId: expect.any(String),
      })
    );
  });

  test("logs error on non-ok response", async () => {
    global.fetch = jest.fn().mockResolvedValue(fakeResponse(500));

    await tracedFetch("https://example.com/test");

    expect(mockLogger.error).toHaveBeenCalledWith(
      "ApiTrace",
      expect.stringContaining("500"),
      expect.objectContaining({
        status: 500,
        durationMs: expect.any(Number),
      })
    );
  });

  test("logs error and rethrows on network failure", async () => {
    const networkError = new Error("Network failure");
    global.fetch = jest.fn().mockRejectedValue(networkError);

    await expect(
      tracedFetch("https://example.com/test")
    ).rejects.toThrow("Network failure");

    expect(mockLogger.error).toHaveBeenCalledWith(
      "ApiTrace",
      expect.stringContaining("FAILED"),
      expect.objectContaining({
        error: "Network failure",
        durationMs: expect.any(Number),
      })
    );
  });

  test("uses method from init if provided", async () => {
    global.fetch = jest.fn().mockResolvedValue(fakeResponse(201));

    await tracedFetch("https://example.com/api/items", { method: "POST" });

    expect(mockLogger.debug).toHaveBeenCalledWith(
      "ApiTrace",
      expect.stringContaining("POST"),
      expect.any(Object)
    );
  });

  test("returns the response object unchanged", async () => {
    const response = fakeResponse(200);
    global.fetch = jest.fn().mockResolvedValue(response);

    const result = await tracedFetch("https://example.com/test");
    expect(result).toBe(response);
  });

  test("generates unique request IDs per call", async () => {
    global.fetch = jest.fn().mockResolvedValue(fakeResponse(200));

    await tracedFetch("https://example.com/a");
    await tracedFetch("https://example.com/b");

    const firstId = mockLogger.debug.mock.calls[0][2]?.requestId;
    const secondId = mockLogger.debug.mock.calls[1][2]?.requestId;
    expect(firstId).toBeTruthy();
    expect(secondId).toBeTruthy();
    expect(firstId).not.toBe(secondId);
  });
});
