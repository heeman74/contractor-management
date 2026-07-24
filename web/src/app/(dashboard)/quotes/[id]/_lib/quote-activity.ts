import type { Quote } from "@/types/api";

export const QUOTE_STEPPER_STEPS = ["draft", "sent", "viewed", "approved"];

export interface QuoteActivityEvent {
  label: string;
  date: string;
  status: string;
}

/** Builds the ordered activity timeline from a quote's lifecycle timestamps. */
export function buildQuoteActivity(quote: Quote): QuoteActivityEvent[] {
  const candidates: Array<QuoteActivityEvent | null> = [
    { label: "Created", date: quote.created_at, status: "draft" },
    quote.sent_at
      ? { label: "Sent to client", date: quote.sent_at, status: "sent" }
      : null,
    quote.viewed_at
      ? { label: "Viewed by client", date: quote.viewed_at, status: "viewed" }
      : null,
    quote.approved_at
      ? { label: "Approved by client", date: quote.approved_at, status: "approved" }
      : null,
    quote.declined_at
      ? { label: "Declined by client", date: quote.declined_at, status: "declined" }
      : null,
  ];

  return candidates.filter((event): event is QuoteActivityEvent => event !== null);
}
