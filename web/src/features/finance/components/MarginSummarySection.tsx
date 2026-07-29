"use client";

import { Separator } from "@/components/ui/separator";
import { formatCurrency, formatSignedCurrency } from "@/lib/format";
import { FinanceFlagChip } from "./FinanceFlagChip";
import type { MarginSummary, RevenueBasis } from "../types";

const REVENUE_LABEL = "Revenue";
const MARGIN_LABEL = "Margin";
const QUOTED_BASIS_CAPTION = "Based on approved quote — not yet invoiced.";
const MIXED_BASIS_CAPTION = "Includes approved quote amounts not yet invoiced.";
export const INCOMPLETE_CHIP_LABEL = "Incomplete cost data"; // exported: the Phase 35 dashboard reuses these three strings byte-for-byte, so one condition can never carry two names across finance surfaces
export const INCOMPLETE_CAPTION =
  "Margin may overstate profit — some costs are missing or unrated.";
export const NO_REVENUE_NOTE =
  "No revenue recorded — margin will appear once an invoice or approved quote exists.";
const FIGURE_SEPARATOR = " · ";
const CAPTION_CLASS = "text-xs text-gray-500";
const FIGURE_CLASS = "text-sm font-semibold text-gray-900";
const NEGATIVE_FIGURE_CLASS = "text-sm font-semibold text-destructive";

/** "21.0" -> "21", "8.3" -> "8.3" — one decimal from the backend, trailing .0 dropped. */
export function formatMarginPercent(percent: string): string {
  return percent.replace(/\.0$/, "");
}

/** "-350.00" -> "-$350.00" (sign before the symbol) — delegates to the shared helper. */
export function formatMarginDollars(amount: string): string {
  return formatSignedCurrency(amount);
}

/** Revenue + Margin rows appended beneath the breakdown Total (33-UI-SPEC states 1-12). */
export function MarginSummarySection({
  margin,
}: {
  margin: MarginSummary | null | undefined;
}) {
  if (!margin) return null;
  return (
    <div data-testid="margin-section" className="space-y-2">
      <Separator />
      {margin.revenueBasis === "none" ? (
        <NoRevenueNote />
      ) : (
        <>
          <RevenueRow margin={margin} />
          <MarginRow margin={margin} />
        </>
      )}
    </div>
  );
}

function NoRevenueNote() {
  return (
    <p data-testid="margin-no-revenue" className={CAPTION_CLASS}>
      {NO_REVENUE_NOTE}
    </p>
  );
}

function basisCaptionFor(basis: RevenueBasis): string | null {
  if (basis === "quoted") return QUOTED_BASIS_CAPTION;
  if (basis === "mixed") return MIXED_BASIS_CAPTION;
  return null;
}

function RevenueRow({ margin }: { margin: MarginSummary }) {
  const caption = basisCaptionFor(margin.revenueBasis);
  return (
    <>
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-700">{REVENUE_LABEL}</span>
        <span data-testid="margin-revenue">{formatCurrency(margin.revenue ?? "0")}</span>
      </div>
      {caption && (
        <p data-testid="margin-basis-caption" className={CAPTION_CLASS}>
          {caption}
        </p>
      )}
    </>
  );
}

function marginFigure(margin: MarginSummary): string {
  if (margin.margin == null) return "";
  const dollars = formatMarginDollars(margin.margin);
  if (margin.marginPercent == null) return dollars;
  return `${dollars}${FIGURE_SEPARATOR}${formatMarginPercent(margin.marginPercent)}%`;
}

function MarginRow({ margin }: { margin: MarginSummary }) {
  const isNegative = margin.margin?.startsWith("-") ?? false;
  return (
    <>
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-700">{MARGIN_LABEL}</span>
        <span className="flex items-center gap-2">
          {margin.incomplete && (
            <FinanceFlagChip testId="margin-incomplete-chip">
              {INCOMPLETE_CHIP_LABEL}
            </FinanceFlagChip>
          )}
          <span
            data-testid="margin-figure"
            className={isNegative ? NEGATIVE_FIGURE_CLASS : FIGURE_CLASS}
          >
            {marginFigure(margin)}
          </span>
        </span>
      </div>
      {margin.incomplete && (
        <p data-testid="margin-incomplete-caption" className={CAPTION_CLASS}>
          {INCOMPLETE_CAPTION}
        </p>
      )}
    </>
  );
}
