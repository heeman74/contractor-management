"use client";

import { useState, useCallback, useRef } from "react";

// --- Types ---

export interface ToolCall {
  tool: string;
  input: Record<string, unknown>;
  id: string;
}

export interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  toolCalls?: ToolCall[];
  timestamp: Date;
}

export interface TradeScope {
  trade_name: string;
  trade_color: string;
  sort_order: number;
}

interface ConversationResponse {
  id: string;
  company_id: string;
  project_id: string | null;
  scope_id: string | null;
  user_id: string;
  conv_type: string;
  status: string;
  version: number;
  created_at: string;
  updated_at: string;
}

interface CompleteIntakeResponse {
  project_id: string;
  trade_scope_ids: string[];
}

// --- SSE parse logic (exported for unit testing) ---

export interface SSEEvent {
  event: string;
  data: unknown;
}

/**
 * Parses a single SSE chunk (may contain multiple lines from a single event block).
 *
 * SSE event blocks look like:
 *   event: token
 *   data: {"delta":"hello"}
 *
 * Returns null for empty lines or comment-only lines.
 * For data-only lines (no event field), defaults event to "message".
 */
export function parseSSELine(raw: string): SSEEvent | null {
  // Strip trailing newlines
  const block = raw.trimEnd();

  if (!block) return null;

  // Comment line (keep-alive etc.)
  if (block.startsWith(":")) return null;

  const lines = block.split("\n");
  let event = "message";
  let dataStr: string | null = null;

  for (const line of lines) {
    if (line.startsWith("event: ")) {
      event = line.slice("event: ".length).trim();
    } else if (line.startsWith("data: ")) {
      dataStr = line.slice("data: ".length).trim();
    }
  }

  if (dataStr === null) return null;

  let data: unknown;
  try {
    data = JSON.parse(dataStr);
  } catch {
    data = dataStr;
  }

  return { event, data };
}

// --- Hook ---

interface UseIntakeChatState {
  messages: ChatMessage[];
  isStreaming: boolean;
  currentStreamText: string;
  tradeScopes: TradeScope[];
  error: string | null;
  conversationId: string | null;
}

interface UseIntakeChatReturn extends UseIntakeChatState {
  startConversation: (projectId?: string) => Promise<void>;
  sendMessage: (message: string) => Promise<void>;
  completeIntake: (
    projectName: string,
    projectDescription: string | undefined,
    editedTradeScopes: TradeScope[]
  ) => Promise<string>;
  removeTradeScope: (index: number) => void;
  updateTradeScope: (index: number, updates: Partial<TradeScope>) => void;
  reorderTradeScopes: (newOrder: TradeScope[]) => void;
}

export function useIntakeChat(): UseIntakeChatReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const [currentStreamText, setCurrentStreamText] = useState("");
  const [tradeScopes, setTradeScopes] = useState<TradeScope[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(null);

  // Track the assistant message id being streamed
  const streamingMsgIdRef = useRef<string | null>(null);

  const addMessage = useCallback((msg: ChatMessage) => {
    setMessages((prev) => [...prev, msg]);
  }, []);

  const updateLastAssistantMessage = useCallback((content: string, toolCalls?: ToolCall[]) => {
    setMessages((prev) => {
      const copy = [...prev];
      // Find last assistant message
      for (let i = copy.length - 1; i >= 0; i--) {
        if (copy[i].role === "assistant") {
          copy[i] = {
            ...copy[i],
            content,
            ...(toolCalls !== undefined ? { toolCalls } : {}),
          };
          return copy;
        }
      }
      return copy;
    });
  }, []);

  const startConversation = useCallback(async (projectId?: string) => {
    try {
      const qs = projectId ? `?project_id=${encodeURIComponent(projectId)}` : "";
      const res = await fetch(
        `/api/ai-chat?path=${encodeURIComponent(`/api/v1/ai/intake/start${qs}`)}`,
        { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" }
      );

      if (!res.ok) {
        const body = await res.json().catch(() => ({ detail: "Failed to start conversation" }));
        setError((body as { detail?: string }).detail ?? "Failed to start conversation");
        return;
      }

      const conv = (await res.json()) as ConversationResponse;
      setConversationId(conv.id);
      setMessages([]);
      setTradeScopes([]);
      setError(null);
    } catch (e) {
      setError("Failed to start conversation. Please check your connection.");
      console.error("[useIntakeChat] startConversation error:", e);
    }
  }, []);

  const sendMessage = useCallback(
    async (message: string) => {
      if (!conversationId) return;

      setError(null);

      // Add user message
      const userMsg: ChatMessage = {
        id: crypto.randomUUID(),
        role: "user",
        content: message,
        timestamp: new Date(),
      };
      addMessage(userMsg);

      // Add placeholder assistant message
      const assistantMsgId = crypto.randomUUID();
      streamingMsgIdRef.current = assistantMsgId;
      const assistantMsg: ChatMessage = {
        id: assistantMsgId,
        role: "assistant",
        content: "",
        timestamp: new Date(),
      };
      addMessage(assistantMsg);

      setIsStreaming(true);
      setCurrentStreamText("");

      let accumulatedText = "";
      const pendingToolCalls: ToolCall[] = [];

      try {
        const res = await fetch(
          `/api/ai-chat?path=${encodeURIComponent("/api/v1/ai/intake/message")}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ conversation_id: conversationId, message }),
          }
        );

        if (!res.ok) {
          const body = await res.json().catch(() => ({ detail: "AI request failed" }));
          const errMsg = (body as { detail?: string }).detail ?? "AI request failed";
          setError(errMsg);
          updateLastAssistantMessage("Something went wrong. Please try again.");
          setIsStreaming(false);
          return;
        }

        if (!res.body) {
          setError("No response body");
          setIsStreaming(false);
          return;
        }

        const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();

        let buffer = "";

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += value;

          // SSE events are separated by double newlines
          const parts = buffer.split("\n\n");
          buffer = parts.pop() ?? "";

          for (const part of parts) {
            const trimmed = part.trim();
            if (!trimmed) continue;

            const parsed = parseSSELine(trimmed);
            if (!parsed) continue;

            const { event, data } = parsed;

            if (event === "token") {
              const tokenData = data as { delta?: string };
              const delta = tokenData.delta ?? "";
              accumulatedText += delta;
              setCurrentStreamText(accumulatedText);
              updateLastAssistantMessage(accumulatedText);
            } else if (event === "tool_call") {
              const tcData = data as { tool?: string; input?: Record<string, unknown>; id?: string };
              const toolCall: ToolCall = {
                tool: tcData.tool ?? "",
                input: tcData.input ?? {},
                id: tcData.id ?? "",
              };
              pendingToolCalls.push(toolCall);

              if (tcData.tool === "create_trade_scope") {
                const scopeInput = tcData.input as {
                  trade_name?: string;
                  trade_color?: string;
                  sort_order?: number;
                };
                setTradeScopes((prev) => [
                  ...prev,
                  {
                    trade_name: scopeInput.trade_name ?? "",
                    trade_color: scopeInput.trade_color ?? "#6366f1",
                    sort_order: scopeInput.sort_order ?? prev.length,
                  },
                ]);
                // Show transitional message
                const transitional = "Generating your trade breakdown...";
                accumulatedText = transitional;
                updateLastAssistantMessage(transitional, [...pendingToolCalls]);
              } else if (tcData.tool === "ask_clarifying_question") {
                const questionInput = tcData.input as { question?: string };
                if (questionInput.question) {
                  accumulatedText += `\n${questionInput.question}`;
                  updateLastAssistantMessage(accumulatedText);
                }
              }
            } else if (event === "done") {
              updateLastAssistantMessage(
                accumulatedText || "Done.",
                pendingToolCalls.length > 0 ? pendingToolCalls : undefined
              );
              setIsStreaming(false);
              setCurrentStreamText("");
            } else if (event === "error") {
              const errData = data as { message?: string };
              const errMsg = errData.message ?? "Something went wrong.";
              setError(errMsg);
              updateLastAssistantMessage(
                "Something went wrong. Please try again.\n\nIf the problem persists, check your connection and reload."
              );
              setIsStreaming(false);
            }
          }
        }

        // Flush remaining buffer
        if (buffer.trim()) {
          const parsed = parseSSELine(buffer.trim());
          if (parsed?.event === "done") {
            updateLastAssistantMessage(accumulatedText || "Done.");
          }
        }

        setIsStreaming(false);
        setCurrentStreamText("");
      } catch (e) {
        console.error("[useIntakeChat] sendMessage error:", e);
        setError("Connection lost. Please check your internet connection and try again.");
        updateLastAssistantMessage(
          "Connection lost. Please check your internet connection and try again."
        );
        setIsStreaming(false);
        setCurrentStreamText("");
      }
    },
    [conversationId, addMessage, updateLastAssistantMessage]
  );

  const completeIntake = useCallback(
    async (
      projectName: string,
      projectDescription: string | undefined,
      editedTradeScopes: TradeScope[]
    ): Promise<string> => {
      if (!conversationId) throw new Error("No active conversation");

      const res = await fetch(
        `/api/ai-chat?path=${encodeURIComponent("/api/v1/ai/intake/complete")}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            conversation_id: conversationId,
            trade_scopes: editedTradeScopes,
            project_name: projectName,
            project_description: projectDescription,
          }),
        }
      );

      if (!res.ok) {
        const body = await res.json().catch(() => ({ detail: "Failed to complete intake" }));
        throw new Error((body as { detail?: string }).detail ?? "Failed to complete intake");
      }

      const result = (await res.json()) as CompleteIntakeResponse;
      return result.project_id;
    },
    [conversationId]
  );

  const removeTradeScope = useCallback((index: number) => {
    setTradeScopes((prev) => prev.filter((_, i) => i !== index));
  }, []);

  const updateTradeScope = useCallback(
    (index: number, updates: Partial<TradeScope>) => {
      setTradeScopes((prev) =>
        prev.map((scope, i) => (i === index ? { ...scope, ...updates } : scope))
      );
    },
    []
  );

  const reorderTradeScopes = useCallback((newOrder: TradeScope[]) => {
    setTradeScopes(newOrder.map((scope, i) => ({ ...scope, sort_order: i })));
  }, []);

  return {
    messages,
    isStreaming,
    currentStreamText,
    tradeScopes,
    error,
    conversationId,
    startConversation,
    sendMessage,
    completeIntake,
    removeTradeScope,
    updateTradeScope,
    reorderTradeScopes,
  };
}
