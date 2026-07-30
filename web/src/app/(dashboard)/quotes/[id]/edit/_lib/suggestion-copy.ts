import {
  UNBURDENED_BODY,
  UNBURDENED_TITLE as UNBURDENED_CAPTION_TITLE,
} from "@/features/finance/components/CostBreakdownSummary";

// ---------------------------------------------------------------------------
// Trigger copy (byte-locked by 37-UI-SPEC)
// ---------------------------------------------------------------------------

export const SUGGEST_LABEL = "Suggest line items";
export const SUGGEST_AGAIN_LABEL = "Suggest again";
export const SUGGEST_PENDING_LABEL = "Analyzing history...";

export const UNSAVED_QUOTE_REASON =
  "Save this draft first — suggestions read the quote's trade.";
export const DIRTY_FORM_REASON =
  "Save your changes first — suggesting rewrites the line items.";

export const SUGGEST_ERROR_MESSAGE = "Couldn't generate suggestions. Try again.";

/** `Suggest line items` before any AI line exists, `Suggest again` once one does;
 *  the pending label wins over either while the mutation is in flight. */
export function triggerLabel(aiLineCount: number, isPending: boolean): string {
  if (isPending) return SUGGEST_PENDING_LABEL;
  return aiLineCount === 0 ? SUGGEST_LABEL : SUGGEST_AGAIN_LABEL;
}

/** null means the trigger is enabled. An unsaved new quote wins over a dirty
 *  form — there is nothing to save-then-suggest-against yet. */
export function triggerDisabledReason({
  isNewQuote,
  isDirty,
}: {
  isNewQuote: boolean;
  isDirty: boolean;
}): string | null {
  if (isNewQuote) return UNSAVED_QUOTE_REASON;
  if (isDirty) return DIRTY_FORM_REASON;
  return null;
}

// ---------------------------------------------------------------------------
// Refusal copy — one map, so a reason can never carry two texts
// ---------------------------------------------------------------------------

export type RefusalReason = "insufficient_history" | "trade_unresolved" | "ungrounded";

export interface SuggestionRefusalContext {
  tradeName: string | null;
  comparableCount: number | null;
  requiredCount: number | null;
}

const REFUSAL_COPY: Record<
  RefusalReason,
  {
    heading: (ctx: SuggestionRefusalContext) => string;
    body: (ctx: SuggestionRefusalContext) => string;
  }
> = {
  insufficient_history: {
    heading: (ctx) => `Not enough ${ctx.tradeName} history yet`,
    // requiredCount and comparableCount are rendered from the response, never
    // from a client constant — the threshold is a backend constant with
    // exactly one home.
    body: (ctx) =>
      `AI suggestions need at least ${ctx.requiredCount} completed ${ctx.tradeName} jobs with recorded costs and an issued invoice. You have ${ctx.comparableCount}. Record costs as work happens and invoice completed jobs — suggestions turn on by themselves.`,
  },
  trade_unresolved: {
    heading: () => "Add a trade to a line first",
    body: () =>
      "Suggestions match a line's trade against your completed work in that trade. Fill in the Trade column on at least one line, save the draft, then try again.",
  },
  ungrounded: {
    heading: () => "No suggestions this time",
    body: () =>
      "The AI's draft cited figures that aren't in your recorded history, so it was discarded rather than shown. Try again, or build the lines by hand.",
  },
};

export function suggestionRefusalCopy(
  reason: RefusalReason,
  context: SuggestionRefusalContext
): { heading: string; body: string } {
  const copy = REFUSAL_COPY[reason];
  return { heading: copy.heading(context), body: copy.body(context) };
}

// ---------------------------------------------------------------------------
// Card captions this module owns
// ---------------------------------------------------------------------------

export const PRICING_BASIS_CAPTION =
  "Suggested prices come from what you charged for comparable work — not from your recorded cost. The cost comparison is in each line's basis.";

// Composed, never retyped — PITFALLS #2's caveat can never carry two texts.
export const UNBURDENED_LABOR_CAPTION = `${UNBURDENED_CAPTION_TITLE}: ${UNBURDENED_BODY}`;
