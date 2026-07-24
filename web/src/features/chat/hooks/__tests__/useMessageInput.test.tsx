import { act, renderHook, waitFor } from "@testing-library/react";
import type { ChangeEvent } from "react";
import {
  findMentionQuery,
  resolveMentionedIds,
  useMessageInput,
  type ThreadMember,
} from "../useMessageInput";

// ---------------------------------------------------------------------------
// Environment stubs — jsdom lacks these APIs the hook depends on.
// ---------------------------------------------------------------------------
const cryptoObj = globalThis.crypto as (Crypto & { randomUUID?: () => string }) | undefined;
if (typeof cryptoObj?.randomUUID !== "function") {
  Object.defineProperty(globalThis, "crypto", {
    configurable: true,
    value: { ...(cryptoObj ?? {}), randomUUID: () => "stub-uuid" },
  });
}

beforeAll(() => {
  jest
    .spyOn(globalThis.crypto, "randomUUID")
    .mockReturnValue("11111111-2222-3333-4444-555555555555");
  globalThis.URL.createObjectURL = jest.fn(() => "blob:mock-preview");
  globalThis.URL.revokeObjectURL = jest.fn();
});

afterEach(() => {
  jest.clearAllMocks();
  (globalThis.fetch as jest.Mock | undefined)?.mockReset?.();
});

const MEMBERS: ThreadMember[] = [
  { user_id: "u-john", name: "John Doe" },
  { user_id: "u-jane", name: "Jane Roe" },
];

/**
 * Build a ChangeEvent whose target is a real <textarea> so that
 * autoGrowTextarea (getComputedStyle / scrollHeight) works, with the caret
 * pinned at `cursor`.
 */
function changeEvent(value: string, cursor = value.length): ChangeEvent<HTMLTextAreaElement> {
  const el = document.createElement("textarea");
  document.body.appendChild(el);
  el.value = value;
  Object.defineProperty(el, "selectionStart", { configurable: true, value: cursor });
  return { target: el } as unknown as ChangeEvent<HTMLTextAreaElement>;
}

function fileChangeEvent(file: File): ChangeEvent<HTMLInputElement> {
  return {
    target: { files: [file], value: "" },
  } as unknown as ChangeEvent<HTMLInputElement>;
}

function setup(overrides: Partial<Parameters<typeof useMessageInput>[0]> = {}) {
  const onSend = jest.fn();
  const onTyping = jest.fn();
  const view = renderHook(() =>
    useMessageInput({
      threadId: "thread-1",
      members: MEMBERS,
      onSend,
      onTyping,
      ...overrides,
    })
  );
  return { ...view, onSend, onTyping };
}

// ---------------------------------------------------------------------------
// Pure helper: findMentionQuery
// ---------------------------------------------------------------------------
describe("findMentionQuery", () => {
  test("returns query and start index for an in-progress mention", () => {
    expect(findMentionQuery("hello @jo")).toEqual({ query: "jo", startIndex: 6 });
  });

  test("matches a bare @ with an empty query", () => {
    expect(findMentionQuery("@")).toEqual({ query: "", startIndex: 0 });
  });

  test("returns null when there is no mention token", () => {
    expect(findMentionQuery("hello")).toBeNull();
  });

  test("returns null once the mention is terminated by whitespace", () => {
    expect(findMentionQuery("hi @jo ")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Pure helper: resolveMentionedIds
// ---------------------------------------------------------------------------
describe("resolveMentionedIds", () => {
  test("maps first-name mentions to member ids", () => {
    expect(resolveMentionedIds("@John hi @Jane", MEMBERS)).toEqual(["u-john", "u-jane"]);
  });

  test("excludes the @all broadcast token", () => {
    expect(resolveMentionedIds("@all listen up", MEMBERS)).toEqual([]);
  });

  test("ignores mentions that match no member", () => {
    expect(resolveMentionedIds("@Nobody there", MEMBERS)).toEqual([]);
  });

  test("keeps real mentions alongside @all", () => {
    expect(resolveMentionedIds("@John and @all", MEMBERS)).toEqual(["u-john"]);
  });
});

// ---------------------------------------------------------------------------
// Hook: useMessageInput
// ---------------------------------------------------------------------------
describe("useMessageInput", () => {
  test("starts empty with no suggestions", () => {
    const { result } = setup();
    expect(result.current.text).toBe("");
    expect(result.current.isEmpty).toBe(true);
    expect(result.current.mentionOpen).toBe(false);
    expect(result.current.suggestions).toEqual([]);
  });

  test("typing plain text updates state without opening mentions", () => {
    const { result } = setup();
    act(() => result.current.handleChange(changeEvent("on my way")));
    expect(result.current.text).toBe("on my way");
    expect(result.current.isEmpty).toBe(false);
    expect(result.current.mentionOpen).toBe(false);
  });

  test("opening a mention filters members by prefix", () => {
    const { result } = setup();
    act(() => result.current.handleChange(changeEvent("@jo")));
    expect(result.current.mentionOpen).toBe(true);
    expect(result.current.suggestions.map((m) => m.name)).toEqual(["John Doe"]);
  });

  test("a bare @ suggests @all plus every member", () => {
    const { result } = setup();
    act(() => result.current.handleChange(changeEvent("@")));
    expect(result.current.suggestions.map((m) => m.name)).toEqual([
      "all",
      "John Doe",
      "Jane Roe",
    ]);
  });

  test("insertMention replaces the in-progress token with the full name", () => {
    const { result } = setup();
    act(() => result.current.handleChange(changeEvent("@jo")));
    act(() => result.current.insertMention(MEMBERS[0]));
    expect(result.current.text).toBe("@John Doe ");
    expect(result.current.mentionOpen).toBe(false);
  });

  test("handleSend builds a payload with resolved mentions and clears the input", async () => {
    const { result, onSend } = setup();
    act(() => result.current.handleChange(changeEvent("  @John ping  ")));
    await act(async () => {
      await result.current.handleSend();
    });
    expect(onSend).toHaveBeenCalledTimes(1);
    expect(onSend.mock.calls[0][0]).toEqual({
      id: "11111111-2222-3333-4444-555555555555",
      content: "@John ping",
      mentions: ["u-john"],
      mention_all: undefined,
    });
    expect(result.current.text).toBe("");
  });

  test("handleSend sets mention_all for an @all broadcast", async () => {
    const { result, onSend } = setup();
    act(() => result.current.handleChange(changeEvent("@all standup now")));
    await act(async () => {
      await result.current.handleSend();
    });
    expect(onSend.mock.calls[0][0].mention_all).toBe(true);
    expect(onSend.mock.calls[0][0].mentions).toBeUndefined();
  });

  test("handleSend is a no-op when there is no text and no file", async () => {
    const { result, onSend } = setup();
    await act(async () => {
      await result.current.handleSend();
    });
    expect(onSend).not.toHaveBeenCalled();
  });

  test("staging an image file exposes a preview and marks the input non-empty", () => {
    const { result } = setup();
    const file = new File(["x"], "photo.png", { type: "image/png" });
    act(() => result.current.handleFileChange(fileChangeEvent(file)));
    expect(result.current.stagedFile).toBe(file);
    expect(result.current.stagedPreviewUrl).toBe("blob:mock-preview");
    expect(result.current.isEmpty).toBe(false);
  });

  test("removeStagedFile clears the staged attachment and revokes its preview", () => {
    const { result } = setup();
    const file = new File(["x"], "photo.png", { type: "image/png" });
    act(() => result.current.handleFileChange(fileChangeEvent(file)));
    act(() => result.current.removeStagedFile());
    expect(result.current.stagedFile).toBeNull();
    expect(result.current.stagedPreviewUrl).toBeNull();
    expect(globalThis.URL.revokeObjectURL).toHaveBeenCalledWith("blob:mock-preview");
  });

  test("handleSend uploads a staged file and forwards the attachment fields", async () => {
    globalThis.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        attachment_url: "/files/chat/photo.png",
        attachment_type: "image",
      }),
    });
    const { result, onSend } = setup();
    const file = new File(["x"], "photo.png", { type: "image/png" });
    act(() => result.current.handleFileChange(fileChangeEvent(file)));
    await act(async () => {
      await result.current.handleSend();
    });

    const [url, init] = (globalThis.fetch as jest.Mock).mock.calls[0];
    expect(url).toContain("/api/proxy?path=");
    expect(url).toContain(encodeURIComponent("/api/v1/chat/threads/thread-1/messages"));
    expect(init.method).toBe("POST");
    expect(init.body).toBeInstanceOf(FormData);

    expect(onSend.mock.calls[0][0]).toMatchObject({
      attachment_url: "/files/chat/photo.png",
      attachment_type: "image",
    });
    expect(result.current.stagedFile).toBeNull();
  });

  test("handleSend still sends when the upload fails", async () => {
    globalThis.fetch = jest.fn().mockResolvedValue({ ok: false, json: async () => ({}) });
    const { result, onSend } = setup();
    const file = new File(["x"], "photo.png", { type: "image/png" });
    act(() => result.current.handleFileChange(fileChangeEvent(file)));
    await act(async () => {
      await result.current.handleSend();
    });
    expect(onSend).toHaveBeenCalledTimes(1);
    expect(onSend.mock.calls[0][0].attachment_url).toBeUndefined();
  });

  test("Ctrl+Enter triggers a send", async () => {
    const { result, onSend } = setup();
    act(() => result.current.handleChange(changeEvent("quick note")));
    const preventDefault = jest.fn();
    act(() => {
      result.current.handleKeyDown({
        key: "Enter",
        ctrlKey: true,
        metaKey: false,
        preventDefault,
      } as unknown as React.KeyboardEvent<HTMLTextAreaElement>);
    });
    expect(preventDefault).toHaveBeenCalled();
    await waitFor(() => expect(onSend).toHaveBeenCalledTimes(1));
  });

  test("debounced typing notification fires after keystrokes", () => {
    jest.useFakeTimers();
    try {
      const { result, onTyping } = setup();
      act(() => result.current.handleChange(changeEvent("h")));
      expect(onTyping).not.toHaveBeenCalled();
      act(() => jest.advanceTimersByTime(500));
      expect(onTyping).toHaveBeenCalledTimes(1);
    } finally {
      jest.useRealTimers();
    }
  });
});
