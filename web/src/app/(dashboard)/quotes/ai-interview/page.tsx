"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Bot, Loader2, Send } from "lucide-react";

import { Input } from "@/components/ui/input";
import {
  type QuoteInterviewResult,
  useQuoteInterviewChat,
} from "@/features/ai/hooks/useQuoteInterviewChat";

/**
 * AI quote interview.
 *
 * The assistant asks about the job one question at a time, then proposes a
 * scope. Creating the quote prices it server-side — grounded in company
 * history where there is enough of it, marked "No history" where there is not.
 * Either way every line lands needing review, so nothing here can be sent
 * without a human reading it.
 */
export default function QuoteInterviewPage() {
  const router = useRouter();
  const {
    messages,
    isStreaming,
    proposal,
    setProposal,
    error,
    conversationId,
    startConversation,
    sendMessage,
    createQuote,
  } = useQuoteInterviewChat();

  const [draft, setDraft] = useState("");
  const [creating, setCreating] = useState(false);
  const [result, setResult] = useState<QuoteInterviewResult | null>(null);
  const startedRef = useRef(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (startedRef.current) return;
    startedRef.current = true;
    void startConversation();
  }, [startConversation]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  async function onSend(event: React.FormEvent) {
    event.preventDefault();
    const text = draft.trim();
    if (!text || isStreaming) return;
    setDraft("");
    await sendMessage(text);
  }

  async function onCreate() {
    if (!proposal) return;
    setCreating(true);
    const created = await createQuote(proposal);
    setCreating(false);
    if (created) {
      setResult(created);
      if (created.suggested_line_count > 0) {
        router.push(`/quotes/${created.quote_id}`);
      }
    }
  }

  return (
    <div className="mx-auto flex h-[calc(100vh-8rem)] w-full max-w-3xl flex-col gap-4 p-4">
      <header className="flex items-center gap-2">
        <Bot className="h-5 w-5 text-brand" aria-hidden />
        <h1 className="text-lg font-semibold text-gray-900">AI quote</h1>
      </header>

      <div
        className="flex-1 space-y-3 overflow-y-auto rounded-lg border border-gray-200 bg-white p-4"
        role="log"
        aria-live="polite"
        aria-label="Quote interview conversation"
      >
        {messages.map((message) => (
          <div
            key={message.id}
            className={message.role === "user" ? "text-right" : "text-left"}
          >
            <span
              className={
                message.role === "user"
                  ? "inline-block rounded-lg bg-brand px-3 py-2 text-sm text-brand-foreground"
                  : "inline-block rounded-lg bg-gray-100 px-3 py-2 text-sm text-gray-900"
              }
            >
              {message.content || (isStreaming ? "…" : "")}
            </span>
          </div>
        ))}
        <div ref={bottomRef} />
      </div>

      {error ? (
        <p role="alert" className="text-sm text-red-600">
          {error}
        </p>
      ) : null}

      {result && result.suggested_line_count === 0 ? (
        <p role="alert" className="text-sm text-amber-700">
          The assistant could not turn that into priced lines. The draft quote was
          created empty — open it and add the lines yourself.
        </p>
      ) : null}

      {proposal ? (
        <section className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <h2 className="text-sm font-medium text-gray-900">Proposed quote</h2>
          <p className="mt-1 text-xs text-gray-600">
            Prices are worked out after you create this. Lines with no comparable
            history are marked and still need your review before the quote can be
            sent.
          </p>
          <label className="mt-3 block text-xs font-medium text-gray-700" htmlFor="quote-title">
            Title
          </label>
          <Input
            id="quote-title"
            value={proposal.title}
            onChange={(event) => setProposal({ ...proposal, title: event.target.value })}
          />
          <label className="mt-3 block text-xs font-medium text-gray-700" htmlFor="quote-trade">
            Trade
          </label>
          <Input
            id="quote-trade"
            value={proposal.trade}
            onChange={(event) => setProposal({ ...proposal, trade: event.target.value })}
          />
          <p className="mt-3 whitespace-pre-wrap text-xs text-gray-700">{proposal.brief}</p>
          <button
            type="button"
            onClick={onCreate}
            disabled={creating || !proposal.title.trim() || !proposal.trade.trim()}
            className="mt-3 inline-flex h-9 items-center gap-1.5 rounded-lg bg-brand px-3 text-sm font-medium text-brand-foreground transition-colors hover:bg-brand/90 disabled:opacity-50"
          >
            {creating ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : null}
            Create draft quote
          </button>
        </section>
      ) : null}

      <form onSubmit={onSend} className="flex items-center gap-2">
        <Input
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          placeholder="Answer here…"
          aria-label="Your answer"
          disabled={!conversationId || isStreaming}
        />
        <button
          type="submit"
          disabled={!conversationId || isStreaming || !draft.trim()}
          className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-brand px-3 text-sm font-medium text-brand-foreground disabled:opacity-50"
        >
          {isStreaming ? (
            <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
          ) : (
            <Send className="h-4 w-4" aria-hidden />
          )}
          Send
        </button>
      </form>
    </div>
  );
}
