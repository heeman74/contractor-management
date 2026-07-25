import { act, renderHook } from "@testing-library/react";

// Mock only aiChatFetch; keep the real ApiError / isSessionExpiredError /
// SESSION_EXPIRED_MESSAGE so the hook's session-expired branch runs for real.
jest.mock("@/lib/api-client", () => {
  const actual = jest.requireActual("@/lib/api-client");
  return { ...actual, aiChatFetch: jest.fn() };
});

import {
  aiChatFetch,
  ApiError,
  SESSION_EXPIRED_MESSAGE,
} from "@/lib/api-client";
import { useIntakeChat } from "../useIntakeChat";

const mockedFetch = aiChatFetch as jest.MockedFunction<typeof aiChatFetch>;

const cryptoObj = globalThis.crypto as (Crypto & { randomUUID?: () => string }) | undefined;
if (typeof cryptoObj?.randomUUID !== "function") {
  Object.defineProperty(globalThis, "crypto", {
    configurable: true,
    value: { ...(cryptoObj ?? {}), randomUUID: () => "stub-uuid" },
  });
}

function ok(body: unknown): Response {
  return { ok: true, status: 200, json: async () => body } as unknown as Response;
}

afterEach(() => jest.clearAllMocks());

test("a dead session (401 that cannot be refreshed) shows the session-expired message, not a generic error", async () => {
  const { result } = renderHook(() => useIntakeChat());

  // Start succeeds so we have a conversation to send into.
  mockedFetch.mockResolvedValueOnce(ok({ id: "conv-1" }));
  await act(async () => {
    await result.current.startConversation();
  });
  expect(result.current.conversationId).toBe("conv-1");

  // The message send hits an unrecoverable 401 — aiChatFetch throws after
  // kicking off the login redirect.
  mockedFetch.mockRejectedValueOnce(new ApiError(401, "Session expired"));
  await act(async () => {
    await result.current.sendMessage("replace a 150A panel");
  });

  expect(result.current.error).toBe(SESSION_EXPIRED_MESSAGE);
  expect(result.current.isStreaming).toBe(false);
  // The assistant bubble reflects the session-expired message, not "Something
  // went wrong / Connection lost".
  const lastAssistant = [...result.current.messages].reverse().find((m) => m.role === "assistant");
  expect(lastAssistant?.content).toBe(SESSION_EXPIRED_MESSAGE);
});

test("a genuine backend/network failure still shows the generic connection error", async () => {
  const { result } = renderHook(() => useIntakeChat());
  mockedFetch.mockResolvedValueOnce(ok({ id: "conv-2" }));
  await act(async () => {
    await result.current.startConversation();
  });

  mockedFetch.mockRejectedValueOnce(new TypeError("network down"));
  await act(async () => {
    await result.current.sendMessage("hello");
  });

  expect(result.current.error).toMatch(/Connection lost/i);
  expect(result.current.error).not.toBe(SESSION_EXPIRED_MESSAGE);
});
