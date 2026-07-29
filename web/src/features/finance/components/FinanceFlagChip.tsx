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
