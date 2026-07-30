"use client";

import type { ReactNode } from "react";

/** The one amber data-quality chip used by every finance honesty flag (unrated hours,
 *  incomplete cost data). Informational, never destructive — a data gap is not an error. */
export const FINANCE_FLAG_CHIP_CLASS =
  "rounded-full bg-brand/15 px-2 py-0.5 text-xs text-amber-900";

/** The red tier chip shared by the Over-budget row badge and the critical-band
 *  finding chip. Two red chips in one feature must never be authored twice. */
export const FINANCE_ALERT_CHIP_CLASS =
  "rounded-full bg-red-100 px-2 py-0.5 text-xs text-red-800";

/** The quietest chip in the ladder: an edge and nothing else. Used where the
 *  evidence is thick and the mark should state that and get out of the way. */
export const FINANCE_OUTLINE_CHIP_CLASS =
  "rounded-full border border-gray-300 px-2 py-0.5 text-xs text-gray-600";

/** One step up: a filled neutral note. The border is load-bearing — the fill is
 *  1.21:1 on white, so without an edge the chip dissolves into its surface. */
export const FINANCE_NOTE_CHIP_CLASS =
  "rounded-full border border-gray-300 bg-secondary px-2 py-0.5 text-xs text-gray-700";

export function FinanceFlagChip({
  children,
  testId,
}: {
  children: ReactNode;
  testId: string;
}) {
  return (
    <span data-testid={testId} className={FINANCE_FLAG_CHIP_CLASS}>
      {children}
    </span>
  );
}
