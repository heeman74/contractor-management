/**
 * The quote interview hook.
 *
 * The behaviour worth pinning is the tool handoff: `propose_quote` must be
 * picked out of the SSE stream and must carry no prices, because prices are
 * produced server-side where they can be grounded or marked rough.
 */
import { act, renderHook, waitFor } from "@testing-library/react";

jest.mock("@/lib/api-client", () => ({ aiChatFetch: jest.fn() }));

import { aiChatFetch } from "@/lib/api-client";
import { useQuoteInterviewChat } from "../useQuoteInterviewChat";

const mockFetch = aiChatFetch as jest.MockedFunction<typeof aiChatFetch>;

// jsdom has neither TextDecoderStream nor ReadableStream, and the hook decodes
// with `body.pipeThrough(new TextDecoderStream()).getReader()`. Stubbing that
// shape is closer to what the hook actually consumes than polyfilling whole
// web-stream machinery would be.
class StubDecoderStream {}
(globalThis as unknown as { TextDecoderStream: unknown }).TextDecoderStream =
  StubDecoderStream;

function streamResponse(blocks: string[]): Response {
  let index = 0;
  const reader = {
    read: async () =>
      index < blocks.length
        ? { done: false, value: blocks[index++] }
        : { done: true, value: undefined },
  };
  return {
    ok: true,
    body: { pipeThrough: () => ({ getReader: () => reader }) },
  } as unknown as Response;
}

function jsonResponse(body: unknown, ok = true): Response {
  return { ok, json: async () => body } as unknown as Response;
}

beforeEach(() => {
  mockFetch.mockReset();
});

async function startedHook() {
  mockFetch.mockResolvedValueOnce(jsonResponse({ id: "conv-1" }));
  const { result } = renderHook(() => useQuoteInterviewChat());
  await act(async () => {
    await result.current.startConversation();
  });
  return result;
}

it("opens with a question and records the conversation", async () => {
  const result = await startedHook();
  expect(result.current.conversationId).toBe("conv-1");
  expect(result.current.messages[0].role).toBe("assistant");
  expect(result.current.messages[0].content).toMatch(/trade/i);
});

it("streams assistant tokens into the transcript", async () => {
  const result = await startedHook();
  mockFetch.mockResolvedValueOnce(
    streamResponse([
      'event: token\ndata: {"delta":"How many "}\n\n',
      'event: token\ndata: {"delta":"bathrooms?"}\n\n',
    ])
  );

  await act(async () => {
    await result.current.sendMessage("Plumbing");
  });

  await waitFor(() => {
    const last = result.current.messages[result.current.messages.length - 1];
    expect(last.content).toBe("How many bathrooms?");
  });
});

it("captures propose_quote as the handoff", async () => {
  const result = await startedHook();
  mockFetch.mockResolvedValueOnce(
    streamResponse([
      'event: tool_call\ndata: {"tool":"propose_quote","input":{"trade":"Plumbing","title":"3-bath rough-in","brief":"Three bathrooms, renovation."}}\n\n',
    ])
  );

  await act(async () => {
    await result.current.sendMessage("Three bathrooms");
  });

  await waitFor(() => {
    expect(result.current.proposal).toEqual({
      trade: "Plumbing",
      title: "3-bath rough-in",
      brief: "Three bathrooms, renovation.",
    });
  });
});

it("ignores a tool call that is not propose_quote", async () => {
  const result = await startedHook();
  mockFetch.mockResolvedValueOnce(
    streamResponse(['event: tool_call\ndata: {"tool":"create_trade_scope","input":{}}\n\n'])
  );

  await act(async () => {
    await result.current.sendMessage("hi");
  });

  expect(result.current.proposal).toBeNull();
});

it("sends no prices when creating the quote", async () => {
  const result = await startedHook();
  mockFetch.mockResolvedValueOnce(
    jsonResponse({
      quote_id: "q-1",
      refusal_reason: null,
      trade_name: "Plumbing",
      comparable_count: 0,
      required_count: 3,
      suggested_line_count: 2,
      grounded: false,
    })
  );

  let created: unknown;
  await act(async () => {
    created = await result.current.createQuote({
      trade: "Plumbing",
      title: "3-bath rough-in",
      brief: "Three bathrooms.",
    });
  });

  expect((created as { quote_id: string }).quote_id).toBe("q-1");
  const body = JSON.parse(
    (mockFetch.mock.calls[1][1] as { body: string }).body
  ) as Record<string, unknown>;
  expect(Object.keys(body).sort()).toEqual(
    ["brief", "conversation_id", "title", "trade"].sort()
  );
});

it("surfaces a failure to create rather than pretending it worked", async () => {
  const result = await startedHook();
  mockFetch.mockResolvedValueOnce(jsonResponse({ detail: "Conversation is not active" }, false));

  let created: unknown = "unset";
  await act(async () => {
    created = await result.current.createQuote({ trade: "P", title: "T", brief: "B" });
  });

  expect(created).toBeNull();
  await waitFor(() => expect(result.current.error).toBe("Conversation is not active"));
});
