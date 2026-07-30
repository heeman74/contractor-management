import type { QuoteConfidenceBand, QuoteLineReviewState } from "@/types/api";
import {
  FINANCE_FLAG_CHIP_CLASS,
  FINANCE_NOTE_CHIP_CLASS,
  FINANCE_OUTLINE_CHIP_CLASS,
} from "@/features/finance/components/FinanceFlagChip";

// The chip grades how much history stands behind a number, not whether the
// number is right — that inversion is why loudness rises as evidence thins,
// and why every band label names the evidence instead of grading it.

export const QUOTE_CONFIDENCE_CHIP: Record<
  QuoteConfidenceBand,
  { label: string; className: string }
> = {
  high: { label: "Strong history", className: FINANCE_OUTLINE_CHIP_CLASS },
  medium: { label: "Limited history", className: FINANCE_NOTE_CHIP_CLASS },
  low: { label: "Thin history", className: FINANCE_FLAG_CHIP_CLASS },
};

export const REVIEW_MARKER: Record<QuoteLineReviewState, string> = {
  unreviewed: "Needs review",
  accepted: "Accepted",
  edited: "AI-originated, user-edited",
};

export const BASIS_WITHHELD_CAPTION = "Basis hidden — requires finance access.";

export const REVIEW_MARKER_CLASS = {
  unreviewed: "text-xs text-gray-700",
  reviewed: "text-xs text-gray-500",
};
