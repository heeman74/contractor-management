/**
 * Tests for the API client module.
 *
 * We mock the tracedFetch function (used internally by apiClient) rather than
 * the global fetch, since apiClient routes through withTracing.
 */

// Mock the tracing module before importing api-client
jest.mock("@/lib/api/withTracing", () => ({
  tracedFetch: jest.fn(),
}));

// Mock the logger to suppress output
jest.mock("@/lib/logger", () => ({
  logger: {
    debug: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

import { apiClient, apiGet, apiPost, apiPatch, apiDelete, ApiError } from "../api-client";
import { tracedFetch } from "@/lib/api/withTracing";

const mockTracedFetch = tracedFetch as jest.MockedFunction<typeof tracedFetch>;

afterEach(() => {
  jest.clearAllMocks();
});

function mockResponse(status: number, body: unknown, ok?: boolean): Response {
  return {
    ok: ok ?? (status >= 200 && status < 300),
    status,
    json: () => Promise.resolve(body),
    headers: new Headers(),
  } as unknown as Response;
}

describe("ApiError", () => {
  test("has correct name, status, and detail", () => {
    const error = new ApiError(404, "Not found");
    expect(error.name).toBe("ApiError");
    expect(error.status).toBe(404);
    expect(error.detail).toBe("Not found");
    expect(error.message).toBe("Not found");
  });

  test("is an instance of Error", () => {
    const error = new ApiError(500, "Server error");
    expect(error).toBeInstanceOf(Error);
  });
});

describe("apiClient", () => {
  test("returns parsed JSON on success", async () => {
    const data = { id: "1", name: "Test" };
    mockTracedFetch.mockResolvedValue(mockResponse(200, data));

    const result = await apiClient<{ id: string; name: string }>("/test");
    expect(result).toEqual(data);
  });

  test("constructs proxy URL with encoded path", async () => {
    mockTracedFetch.mockResolvedValue(mockResponse(200, {}));

    await apiClient("/api/v1/projects/test path");
    expect(mockTracedFetch).toHaveBeenCalledWith(
      `/api/proxy?path=${encodeURIComponent("/api/v1/projects/test path")}`,
      undefined
    );
  });

  test("passes RequestInit options through", async () => {
    mockTracedFetch.mockResolvedValue(mockResponse(200, {}));
    const init = { method: "POST", body: '{"key":"value"}' };

    await apiClient("/test", init);
    expect(mockTracedFetch).toHaveBeenCalledWith(
      expect.any(String),
      init
    );
  });

  test("throws ApiError with detail from JSON error body", async () => {
    mockTracedFetch.mockResolvedValue(
      mockResponse(422, { detail: "Validation failed" })
    );

    await expect(apiClient("/test")).rejects.toThrow(ApiError);
    await expect(apiClient("/test")).rejects.toMatchObject({
      status: 422,
      detail: "Validation failed",
    });
  });

  test("throws ApiError with default message for non-JSON error body", async () => {
    const resp = {
      ok: false,
      status: 500,
      json: () => Promise.reject(new Error("not json")),
      headers: new Headers(),
    } as unknown as Response;
    mockTracedFetch.mockResolvedValue(resp);

    await expect(apiClient("/test")).rejects.toMatchObject({
      status: 500,
      detail: "An unexpected error occurred",
    });
  });

  test("attempts token refresh on 401 and retries", async () => {
    const refreshResponse = mockResponse(200, {});
    const successResponse = mockResponse(200, { result: "ok" });

    mockTracedFetch.mockResolvedValueOnce(mockResponse(401, {}));

    // Mock global fetch for the refresh call
    global.fetch = jest.fn().mockResolvedValueOnce(refreshResponse);

    mockTracedFetch.mockResolvedValueOnce(successResponse);

    const result = await apiClient("/test");
    expect(result).toEqual({ result: "ok" });
    expect(global.fetch).toHaveBeenCalledWith("/api/auth/refresh", { method: "POST" });
  });

  test("throws session expired error when refresh fails", async () => {
    mockTracedFetch.mockResolvedValue(mockResponse(401, {}));

    const failedRefresh = { ok: false, status: 401 } as Response;
    global.fetch = jest.fn().mockResolvedValue(failedRefresh);

    // window.location.href assignment triggers jsdom "not implemented" but the
    // error throw still happens. We verify the thrown error instead of checking
    // the href value.
    await expect(apiClient("/test")).rejects.toMatchObject({
      status: 401,
      detail: "Session expired",
    });
    // Verify refresh was attempted
    expect(global.fetch).toHaveBeenCalledWith("/api/auth/refresh", { method: "POST" });
  });

  test("does not retry when retry=false", async () => {
    mockTracedFetch.mockResolvedValue(mockResponse(401, {}));
    global.fetch = jest.fn();

    await expect(apiClient("/test", undefined, false)).rejects.toMatchObject({
      status: 401,
    });
    // Should not attempt refresh
    expect(global.fetch).not.toHaveBeenCalled();
  });
});

describe("convenience methods", () => {
  test("apiGet sends GET through proxy", async () => {
    mockTracedFetch.mockResolvedValue(mockResponse(200, []));

    await apiGet("/items");
    expect(mockTracedFetch).toHaveBeenCalledWith(
      "/api/proxy?path=%2Fitems",
      { method: "GET" }
    );
  });

  test("apiPost sends JSON body through proxy", async () => {
    mockTracedFetch.mockResolvedValue(mockResponse(201, { id: "new" }));
    const body = { name: "test" };

    await apiPost("/items", body);
    expect(mockTracedFetch).toHaveBeenCalledWith(
      "/api/proxy?path=%2Fitems",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      }
    );
  });

  test("apiPatch sends JSON body with PATCH method", async () => {
    mockTracedFetch.mockResolvedValue(mockResponse(200, {}));

    await apiPatch("/items/1", { name: "updated" });
    expect(mockTracedFetch).toHaveBeenCalledWith(
      "/api/proxy?path=%2Fitems%2F1",
      {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: "updated" }),
      }
    );
  });

  test("apiDelete uses DELETE method", async () => {
    mockTracedFetch.mockResolvedValue(mockResponse(200, {}));

    await apiDelete("/items/1");
    expect(mockTracedFetch).toHaveBeenCalledWith(
      "/api/proxy?path=%2Fitems%2F1",
      { method: "DELETE" }
    );
  });
});
