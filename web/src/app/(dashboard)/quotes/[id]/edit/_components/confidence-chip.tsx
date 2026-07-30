import type { QuoteConfidenceBand } from "@/types/api";
import { QUOTE_CONFIDENCE_CHIP } from "../_lib/confidence-band";

/**
 * Renders the band chip for a single AI-suggested line item. Deliberately does
 * not reuse the shipped amber-only finance chip component, which hardcodes a
 * single recipe (the Phase 36 severity-chip precedent) — this chip needs all
 * three recipes. Renders nothing for a null band, which is also the
 * `finance.view`-less case.
 */
export function ConfidenceChip({
  band,
  index,
}: {
  band: QuoteConfidenceBand | null;
  index: number;
}) {
  if (band === null) return null;

  const { label, className } = QUOTE_CONFIDENCE_CHIP[band];

  return (
    <span data-testid={`confidence-chip-${index}`} className={className}>
      {label}
    </span>
  );
}
