import { Bot } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { QuoteConfidenceBand, QuoteLineReviewState } from "@/types/api";
import {
  BASIS_WITHHELD_CAPTION,
  REVIEW_MARKER,
  REVIEW_MARKER_CLASS,
} from "../_lib/confidence-band";
import { ConfidenceChip } from "./confidence-chip";

interface AiLineSubRowProps {
  index: number;
  columnCount: number;
  band: QuoteConfidenceBand | null;
  reviewState: QuoteLineReviewState;
  basis: string | null;
  onAccept: () => void;
}

/**
 * One AI-suggested line's provenance row: chip, review marker, an Accept
 * affordance while unreviewed, and the cited basis. Presentational only — no
 * hook, no fetch, no local state.
 *
 * Carries no background class, and never will. The tint belongs to the input
 * row above it; the medium band's note-recipe chip fill measures 1.00:1 fill
 * contrast against that same tint, and the medium band's default state is
 * unreviewed, so a tinted sub-row would render the most common state as two
 * undifferentiated gray strings. See 37-UI-SPEC "the unreviewed-line
 * treatment" for the full reasoning.
 */
export function AiLineSubRow({
  index,
  columnCount,
  band,
  reviewState,
  basis,
  onAccept,
}: AiLineSubRowProps) {
  const isUnreviewed = reviewState === "unreviewed";
  const markerClass = isUnreviewed
    ? REVIEW_MARKER_CLASS.unreviewed
    : REVIEW_MARKER_CLASS.reviewed;

  return (
    <tr data-testid={`ai-line-sub-row-${index}`}>
      <td colSpan={columnCount}>
        <div className="flex items-center gap-2">
          <Bot aria-hidden className="h-3 w-3 text-foreground/70" />
          <ConfidenceChip band={band} index={index} />
          <span data-testid={`review-marker-${index}`} className={markerClass}>
            {REVIEW_MARKER[reviewState]}
          </span>
          {isUnreviewed && (
            <Button
              type="button"
              variant="outline"
              size="sm"
              data-testid={`accept-line-${index}`}
              aria-label={`Accept suggested line ${index + 1}`}
              onClick={onAccept}
            >
              Accept
            </Button>
          )}
        </div>
        <p data-testid={`line-basis-${index}`} className="mt-1 text-xs text-gray-500">
          {basis ?? BASIS_WITHHELD_CAPTION}
        </p>
      </td>
    </tr>
  );
}
