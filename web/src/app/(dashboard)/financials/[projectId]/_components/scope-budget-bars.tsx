"use client";

import {
  BulletBarChart,
  type BulletBarRow,
} from "@/app/(dashboard)/financials/_components/bullet-bar-chart";
import { ChartEmptyState } from "@/components/shared/chart-empty-state";
import { PERCENT_AXIS_CLAMP } from "@/components/shared/chart-theme";
import { clampPercentForAxis } from "@/features/finance/financials-format";
import type { BudgetVsActual, ScopeBudgetRow } from "@/features/finance/types";
import { formatCurrency } from "@/lib/format";

export const SCOPE_BARS_TEST_ID = "scope-budget-bars";
export const SCOPE_BARS_TITLE = "Budget vs Actual by Trade Scope";
export const SCOPE_BARS_CSV_FILENAME = "budget-vs-actual-by-trade-scope.csv";

/** The Phase 30 anchor asymmetry makes every scope bar structurally short; saying
 *  so is the honest alternative to a silently low bar. Exported (Phase 37) so
 *  every trade-scope-anchored quote surface reuses this exact string rather
 *  than retyping it — one condition, one text, one testid (`scope-labor-note`). */
export const LABOR_NOTE = "Scope spend excludes labor — labor is tracked at job level.";
const EMPTY_HEADING = "No scope budgets set";
const EMPTY_BODY = "Set a budget on a trade scope to track its spend.";
const CSV_HEADER = ["Trade scope", "Budget", "Spent", "Percent used"];
const NO_SCOPES = 0;

type BudgetedScope = ScopeBudgetRow & { budget: BudgetVsActual };

function isBudgeted(row: ScopeBudgetRow): row is BudgetedScope {
  return row.budget !== null;
}

/** The one place a scope money string becomes a number: every rendered figure
 *  still formats from the original backend string. */
export function toScopeBarRows(scopes: ScopeBudgetRow[]): BulletBarRow[] {
  const truePercentOf = (row: BudgetedScope) => parseFloat(row.budget.percentUsed);
  return scopes
    .filter(isBudgeted)
    .sort((left, right) => truePercentOf(right) - truePercentOf(left))
    .map((row) => toBulletBarRow(row, truePercentOf(row)));
}

function toBulletBarRow(row: BudgetedScope, truePercent: number): BulletBarRow {
  return {
    id: row.tradeScopeId,
    label: row.tradeName,
    percentUsed: row.budget.percentUsed,
    remaining: row.budget.remaining,
    percentUsedClamped: clampPercentForAxis(row.budget.percentUsed),
    spentLabel: formatCurrency(row.budget.spent),
    budgetLabel: formatCurrency(row.budget.total),
    isOverClamp: truePercent > PERCENT_AXIS_CLAMP,
  };
}

/** Full trade names and true percents: an export never inherits the chart's clamping. */
export function scopeBarsCsvRows(scopes: ScopeBudgetRow[]): string[][] {
  return [
    CSV_HEADER,
    ...scopes
      .filter(isBudgeted)
      .map((row) => [
        row.tradeName,
        row.budget.total,
        row.budget.spent,
        row.budget.percentUsed,
      ]),
  ];
}

export function budgetedScopesKpi(scopes: ScopeBudgetRow[]): string {
  return `${scopes.filter(isBudgeted).length} of ${scopes.length} scopes budgeted`;
}

/**
 * The drill-down's half of the bullet display. Identical form, bands, sort and
 * geometry to the project bars — it consumes the same chart rather than forking
 * it — and differs only in what a row names, its lack of a destination, and the
 * labor caption it is obliged to carry.
 */
export function ScopeBudgetBars({ scopes }: { scopes: ScopeBudgetRow[] }) {
  const rows = toScopeBarRows(scopes);

  if (rows.length === NO_SCOPES) {
    return <ChartEmptyState heading={EMPTY_HEADING} body={EMPTY_BODY} />;
  }

  return (
    <div>
      <BulletBarChart rows={rows} testId={SCOPE_BARS_TEST_ID} />
      <p data-testid="scope-labor-note" className="mt-2 text-xs text-gray-500">
        {LABOR_NOTE}
      </p>
    </div>
  );
}
