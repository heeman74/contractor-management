"use client";

import type { ReactNode } from "react";

import { Card, CardContent } from "@/components/ui/card";
import { FINANCE_FLAG_CHIP_CLASS } from "@/features/finance/components/FinanceFlagChip";
import {
  INCOMPLETE_CAPTION,
  formatMarginDollars,
  formatMarginPercent,
} from "@/features/finance/components/MarginSummarySection";
import type { MarginSummary, RevenueBasis } from "@/features/finance/types";
import { formatCurrency } from "@/lib/format";

/** An absent figure reads as an em dash, never as $0 — a null is honest absence. */
const ABSENT_FIGURE = "—";
const QUOTED_BASIS_CAPTION = "Based on approved quotes — not yet invoiced.";
const NO_REVENUE_CAPTION = "No revenue recorded yet.";
const NEGATIVE_PREFIX = "-";
const NO_INCOMPLETE_PROJECTS = 0;
const SINGLE_INCOMPLETE_PROJECT = 1;

const TILE_GRID_CLASS = "grid grid-cols-1 md:grid-cols-3 gap-8";
const TITLE_CLASS = "text-sm text-gray-500";
const FIGURE_CLASS = "mt-1 text-3xl font-bold text-gray-900";
/** 30px is the one size at which #d64545 clears AA — see 35-UI-SPEC § the red rule. */
const NEGATIVE_FIGURE_CLASS = "mt-1 text-3xl font-bold text-destructive";
const SUBLINE_CLASS = "mt-1 text-sm text-gray-500";
const CAPTION_CLASS = "mt-1 text-xs text-gray-500";

interface FinanceSummaryTilesProps {
  revenueTitle: string;
  costTitle: string;
  marginTitle: string;
  cost: string;
  /** Nullable: the drill-down's breakdown carries no margin until revenue exists. */
  margin: MarginSummary | null;
  testIdPrefix: string;
  /** Portfolio-only (D-09 estimated share). Absent on the drill-down. */
  quotedRevenue?: string | null;
  /** Portfolio-only (D-09 badge). Absent renders exactly like a count of zero. */
  incompleteProjectCount?: number;
}

/** The revenue tile's honesty caption. A mixed basis names the estimated share;
 *  without that amount there is nothing honest to say, so nothing is said. */
export function basisCaption(
  basis: RevenueBasis | undefined,
  quotedRevenue: string | null | undefined
): string | null {
  if (basis === "none") return NO_REVENUE_CAPTION;
  if (basis === "quoted") return QUOTED_BASIS_CAPTION;
  if (basis === "mixed" && quotedRevenue != null) {
    return `Includes ${formatCurrency(quotedRevenue)} from approved quotes — not yet invoiced.`;
  }
  return null;
}

/** Pluralisation lives here so the chip and its aria-label can never disagree. */
export function incompleteBadgeLabel(count: number): string {
  const noun = count === SINGLE_INCOMPLETE_PROJECT ? "project" : "projects";
  return `${count} ${noun} with incomplete data`;
}

function moneyFigure(value: string | null | undefined): string {
  return value == null ? ABSENT_FIGURE : formatCurrency(value);
}

function marginFigure(margin: MarginSummary | null): string {
  return margin?.margin == null ? ABSENT_FIGURE : formatMarginDollars(margin.margin);
}

function marginSubline(margin: MarginSummary | null): string | null {
  if (margin?.marginPercent == null) return null;
  return `${formatMarginPercent(margin.marginPercent)}% margin`;
}

/**
 * The three-figure header shared by both financial routes. A tile is a number,
 * not a chart, so it borrows only ChartCard's typography — no icon box, no export.
 */
export function FinanceSummaryTiles({
  revenueTitle,
  costTitle,
  marginTitle,
  cost,
  margin,
  testIdPrefix,
  quotedRevenue,
  incompleteProjectCount,
}: FinanceSummaryTilesProps) {
  const caption = basisCaption(margin?.revenueBasis, quotedRevenue);
  const incompleteCount = incompleteProjectCount ?? NO_INCOMPLETE_PROJECTS;

  return (
    <div className={TILE_GRID_CLASS}>
      <SummaryTile
        title={revenueTitle}
        figure={moneyFigure(margin?.revenue)}
        testId={`${testIdPrefix}-revenue`}
      >
        {caption && (
          <p data-testid={`${testIdPrefix}-revenue-basis`} className={CAPTION_CLASS}>
            {caption}
          </p>
        )}
      </SummaryTile>

      <SummaryTile
        title={costTitle}
        figure={formatCurrency(cost)}
        testId={`${testIdPrefix}-cost`}
      />

      <SummaryTile
        title={marginTitle}
        figure={marginFigure(margin)}
        subline={marginSubline(margin)}
        sublineTestId={`${testIdPrefix}-margin-percent`}
        testId={`${testIdPrefix}-margin`}
      >
        {incompleteCount > NO_INCOMPLETE_PROJECTS && (
          <IncompleteDataBadge count={incompleteCount} testIdPrefix={testIdPrefix} />
        )}
      </SummaryTile>
    </div>
  );
}

interface SummaryTileProps {
  title: string;
  figure: string;
  testId: string;
  subline?: string | null;
  sublineTestId?: string;
  children?: ReactNode;
}

function SummaryTile({
  title,
  figure,
  testId,
  subline,
  sublineTestId,
  children,
}: SummaryTileProps) {
  const isNegative = figure.startsWith(NEGATIVE_PREFIX);
  return (
    <Card>
      <CardContent className="pt-4">
        <p className={TITLE_CLASS}>{title}</p>
        <p
          data-testid={testId}
          className={isNegative ? NEGATIVE_FIGURE_CLASS : FIGURE_CLASS}
        >
          {figure}
        </p>
        {subline && (
          <p data-testid={sublineTestId} className={SUBLINE_CLASS}>
            {subline}
          </p>
        )}
        {children}
      </CardContent>
    </Card>
  );
}

/** The chip is itself the anchor into the Needs Attention list, so the count and
 *  the rows it counts are one click apart (D-09). */
function IncompleteDataBadge({
  count,
  testIdPrefix,
}: {
  count: number;
  testIdPrefix: string;
}) {
  const label = incompleteBadgeLabel(count);
  return (
    <>
      <a
        href="#attention-list"
        data-testid={`${testIdPrefix}-incomplete-badge`}
        aria-label={`Show the ${label}`}
        className={`mt-1 inline-block ${FINANCE_FLAG_CHIP_CLASS}`}
      >
        {label}
      </a>
      <p data-testid={`${testIdPrefix}-incomplete-caption`} className={CAPTION_CLASS}>
        {INCOMPLETE_CAPTION}
      </p>
    </>
  );
}
