"use client";

import { useCallback, useRef, useState } from "react";

import { aiChatFetch } from "@/lib/api-client";
import { type ChatMessage, parseSSELine } from "./useIntakeChat";

/**
 * The AI quote interview: gather scope by asking, then hand off for pricing.
 *
 * Deliberately thin next to useIntakeChat. There is one tool, `propose_quote`,
 * and it carries no figures — prices are produced server-side so they can be
 * grounded in company history or marked rough. A price arriving over this
 * channel would be a price nothing had vetted.
 */

export interface QuoteProposal {
  trade: string;
  title: string;
  brief: string;
}

export interface QuoteInterviewResult {
  quote_id: string;
  refusal_reason: string | null;
  trade_name: string | null;
  comparable_count: number | null;
  required_count: number | null;
  suggested_line_count: number;
  grounded: boolean;
}

interface ConversationResponse {
  id: string;
}

export function useQuoteInterviewChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const [proposal, setProposal] = useState<QuoteProposal | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const streamingMsgIdRef = useRef<string | null>(null);

  const addMessage = useCallback((msg: ChatMessage) => {
    setMessages((prev) => [...prev, msg]);
  }, []);

  const updateLastAssistantMessage = useCallback((content: string) => {
    const id = streamingMsgIdRef.current;
    setMessages((prev) => prev.map((m) => (m.id === id ? { ...m, content } : m)));
  }, []);

  const startConversation = useCallback(async () => {
    setError(null);
    const res = await aiChatFetch("/api/v1/ai/quote-interview/start", { method: "POST" });
    if (!res.ok) {
      setError("Could not start the interview. Please try again.");
      return;
    }
    const conv = (await res.json()) as ConversationResponse;
    setConversationId(conv.id);
    addMessage({
      id: crypto.randomUUID(),
      role: "assistant",
      content:
        "Let's scope this job. What trade is it — plumbing, electrical, framing, something else?",
      timestamp: new Date(),
    });
  }, [addMessage]);

  const sendMessage = useCallback(
    async (message: string) => {
      if (!conversationId || isStreaming) return;
      setError(null);

      addMessage({
        id: crypto.randomUUID(),
        role: "user",
        content: message,
        timestamp: new Date(),
      });

      const assistantMsgId = crypto.randomUUID();
      streamingMsgIdRef.current = assistantMsgId;
      addMessage({
        id: assistantMsgId,
        role: "assistant",
        content: "",
        timestamp: new Date(),
      });

      setIsStreaming(true);
      let accumulated = "";

      try {
        const res = await aiChatFetch("/api/v1/ai/quote-interview/message", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ conversation_id: conversationId, message }),
        });

        if (!res.ok || !res.body) {
          const body = await res.json().catch(() => ({ detail: "AI request failed" }));
          setError((body as { detail?: string }).detail ?? "AI request failed");
          updateLastAssistantMessage("Something went wrong. Please try again.");
          return;
        }

        const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
        let buffer = "";

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += value;

          const parts = buffer.split("\n\n");
          buffer = parts.pop() ?? "";

          for (const part of parts) {
            const parsed = parseSSELine(part.trim());
            if (!parsed) continue;

            if (parsed.event === "token") {
              accumulated += (parsed.data as { delta?: string }).delta ?? "";
              updateLastAssistantMessage(accumulated);
            } else if (parsed.event === "tool_call") {
              const tc = parsed.data as { tool?: string; input?: Record<string, unknown> };
              if (tc.tool === "propose_quote") {
                const input = tc.input ?? {};
                setProposal({
                  trade: String(input.trade ?? ""),
                  title: String(input.title ?? ""),
                  brief: String(input.brief ?? ""),
                });
              }
            } else if (parsed.event === "error") {
              setError((parsed.data as { message?: string }).message ?? "AI request failed");
            }
          }
        }
      } catch {
        setError("Lost connection to the assistant.");
        updateLastAssistantMessage("Something went wrong. Please try again.");
      } finally {
        setIsStreaming(false);
      }
    },
    [conversationId, isStreaming, addMessage, updateLastAssistantMessage]
  );

  const createQuote = useCallback(
    async (
      edited: QuoteProposal & { client_id: string | null }
    ): Promise<QuoteInterviewResult | null> => {
      if (!conversationId) return null;
      setError(null);
      const res = await aiChatFetch("/api/v1/ai/quote-interview/complete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ conversation_id: conversationId, ...edited }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({ detail: "Could not create the quote." }));
        setError((body as { detail?: string }).detail ?? "Could not create the quote.");
        return null;
      }
      return (await res.json()) as QuoteInterviewResult;
    },
    [conversationId]
  );

  return {
    messages,
    isStreaming,
    proposal,
    setProposal,
    error,
    conversationId,
    startConversation,
    sendMessage,
    createQuote,
  };
}
