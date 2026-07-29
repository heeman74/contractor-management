"use client";

import Link from "next/link";

import { ChartEmptyState } from "@/components/shared/chart-empty-state";
import { StatusBadge } from "@/components/shared/status-badge";
import {
  FINANCE_ALERT_CHIP_CLASS,
  FINANCE_FLAG_CHIP_CLASS,
} from "@/features/finance/components/FinanceFlagChip";
import { NEARING_BUDGET_CHIP_LABEL } from "@/features/finance/components/BudgetSummarySection";
import {
  INCOMPLETE_CAPTION,
  INCOMPLETE_CHIP_LABEL,
  formatMarginPercent,
} from "@/features/finance/components/MarginSummarySection";
import {
  INACTIVE_PROJECT_STATUSES,
  type AttentionRow,
  type AttentionTier,
} from "@/features/finance/types";
import { formatCurrency } from "@/lib/format";

export const ATTENTION_TITLE = "Needs Attention";
export const ATTENTION_CSV_FILENAME = "needs-attention.csv";

const ALL_CLEAR_KPI = "All clear";
const EMPTY_HEADING = "Nothing needs attention";
const EMPTY_BODY =
  "No project is over budget, nearing its budget, or missing cost data.";
const CSV_HEADER = ["Tier", "Project", "Anchor", "Spent", "Budget", "Percent used"];
const EMPTY_CELL = "";
const SINGLE_ROW = 1;
const NO_ROWS = 0;

const OVERRUN_PERCENT_CLASS = "text-sm font-semibold text-red-800";
const WARNING_PERCENT_CLASS = "text-sm font-semibold text-gray-900";
const INACTIVE_ROW_CLASS = "opacity-60";

interface TierBadge {
  label: string;
  className: string;
}

/** One map, so a tier's copy and its colour can never drift apart. */
const TIER_BADGE: Record<AttentionTier, TierBadge> = {
  overrun: { label: "Over budget", className: FINANCE_ALERT_CHIP_CLASS },
  warning: { label: NEARING_BUDGET_CHIP_LABEL, className: FINANCE_FLAG_CHIP_CLASS },
  incomplete: { label: INCOMPLETE_CHIP_LABEL, className: FINANCE_FLAG_CHIP_CLASS },
};

export function tierBadge(tier: AttentionTier): TierBadge {
  return TIER_BADGE[tier];
}

export function attentionKpi(rows: AttentionRow[]): string {
  if (rows.length === NO_ROWS) return ALL_CLEAR_KPI;
  if (rows.length === SINGLE_ROW) return `${SINGLE_ROW} needs attention`;
  return `${rows.length} need attention`;
}

export function attentionCsvRows(rows: AttentionRow[]): string[][] {
  return [
    CSV_HEADER,
    ...rows.map((row) => [
      tierBadge(row.tier).label,
      row.projectName,
      row.anchorLabel,
      row.spent ?? EMPTY_CELL,
      row.budgetTotal ?? EMPTY_CELL,
      row.percentUsed ?? EMPTY_CELL,
    ]),
  ];
}

/** The incomplete tier has no percent: fabricating one would invent a budget
 *  position for a project whose costs are not even known. */
function percentClassFor(tier: AttentionTier): string {
  return tier === "overrun" ? OVERRUN_PERCENT_CLASS : WARNING_PERCENT_CLASS;
}

function sublineFor(row: AttentionRow): string {
  if (row.spent == null || row.budgetTotal == null) return INCOMPLETE_CAPTION;
  return `${formatCurrency(row.spent)} of ${formatCurrency(row.budgetTotal)}`;
}

/**
 * The ordered tier list. Order is the server's (D-08: overrun, then warning, then
 * incomplete) and this component neither sorts nor filters it — the bars above it
 * read the same live spend, so the two can never contradict each other on screen.
 */
export function AttentionList({ rows }: { rows: AttentionRow[] }) {
  if (rows.length === NO_ROWS) {
    return (
      <div data-testid="attention-empty">
        <ChartEmptyState heading={EMPTY_HEADING} body={EMPTY_BODY} />
      </div>
    );
  }

  return (
    // The id is the incomplete-data badge's anchor target, so it belongs on the
    // list element itself and is written out rather than composed.
    <ul id="attention-list" data-testid="attention-list" className="space-y-2">
      {rows.map((row) => (
        <AttentionListRow key={`${row.projectId}-${row.tier}`} row={row} />
      ))}
    </ul>
  );
}

function AttentionListRow({ row }: { row: AttentionRow }) {
  const badge = tierBadge(row.tier);
  const isInactive = INACTIVE_PROJECT_STATUSES.includes(row.projectStatus);

  return (
    <li>
      <Link
        href={`/financials/${row.projectId}`}
        data-testid={`attention-row-${row.projectId}`}
        className={`block rounded-md px-1 py-1 hover:bg-muted/50 ${isInactive ? INACTIVE_ROW_CLASS : ""}`}
      >
        <div className="flex items-center justify-between gap-2">
          <span className="flex items-center gap-2">
            <span className={badge.className}>{badge.label}</span>
            <span className="text-sm font-semibold text-gray-900">{row.anchorLabel}</span>
            {isInactive && <StatusBadge status={row.projectStatus} size="sm" />}
          </span>
          {row.percentUsed != null && (
            <span className={percentClassFor(row.tier)}>
              {formatMarginPercent(row.percentUsed)}%
            </span>
          )}
        </div>
        <p className="mt-1 text-xs text-gray-500">{sublineFor(row)}</p>
      </Link>
    </li>
  );
}
