"use client";

import { Cell, Legend, Pie, PieChart, ResponsiveContainer, Tooltip } from "recharts";

import { ChartEmptyState } from "@/components/shared/chart-empty-state";
import {
  CATEGORY_FILL,
  CHART_HEIGHT,
  CHART_TICK,
  CHART_TOOLTIP_STYLE,
  CUSTOM_CATEGORY_FILLS,
  PIE_LABEL_MIN_PERCENT,
} from "@/components/shared/chart-theme";
import { formatMarginPercent } from "@/features/finance/components/MarginSummarySection";
import {
  rollUpCategories,
  type CategorySlice,
} from "@/features/finance/financials-format";
import type { CategoryTotal, LaborCostSummary } from "@/features/finance/types";
import { formatCurrency } from "@/lib/format";

export const CATEGORY_MIX_TITLE = "Cost Category Mix";
export const CATEGORY_MIX_CSV_FILENAME = "cost-category-mix.csv";
export const CATEGORY_MIX_TEST_ID = "category-mix-chart";

/** Derived labor is a category of spend to the reader, even though the backend
 *  keeps it out of the category list (Phase 32). */
const LABOR_CATEGORY_NAME = "Labor";
const EMPTY_HEADING = "No costs recorded";
const EMPTY_BODY = "Add a cost entry or tracked time to see where the money goes.";
const CSV_HEADER = ["Category", "Amount", "Percent of total"];
const DETAIL_SEPARATOR = " · ";
const SUPPRESSED_LABEL = "";
const NO_MONEY = 0;
const NO_CATEGORIES = 0;
const PERCENT_MULTIPLIER = 100;
const PERCENT_DECIMALS = 1;
const OUTER_RADIUS = 90;

interface NamedAmount {
  name: string;
  amount: string;
}

/** Labor leads the list; the rollup then sorts everything by size. */
function toNamedAmounts(
  categories: CategoryTotal[],
  labor: LaborCostSummary | null
): NamedAmount[] {
  const laborRows = labor ? [{ name: LABOR_CATEGORY_NAME, amount: labor.total }] : [];
  return [
    ...laborRows,
    ...categories.map((category) => ({
      name: category.categoryName,
      amount: category.total,
    })),
  ];
}

/** The pie's only client-side arithmetic: the rollup bucket is a real sum, so it
 *  needs numbers. Every figure outside the geometry still comes from a string. */
export function toCategorySlices(
  categories: CategoryTotal[],
  labor: LaborCostSummary | null
): CategorySlice[] {
  return rollUpCategories(
    toNamedAmounts(categories, labor).map((row) => ({
      name: row.name,
      amount: parseFloat(row.amount),
    }))
  );
}

function totalOf(slices: CategorySlice[]): number {
  return slices.reduce((sum, slice) => sum + slice.amount, NO_MONEY);
}

function percentOfTotal(amount: number, total: number): string {
  if (total <= NO_MONEY) return formatMarginPercent(NO_MONEY.toFixed(PERCENT_DECIMALS));
  const percent = (amount / total) * PERCENT_MULTIPLIER;
  return formatMarginPercent(percent.toFixed(PERCENT_DECIMALS));
}

function reservedFillFor(slice: CategorySlice): string | undefined {
  return CATEGORY_FILL[slice.name.toLowerCase()];
}

/** Company-custom categories take the two reserved custom hues first, then any
 *  system hue no slice claimed — which is what keeps the capped ramp repeat-free. */
function customFillPool(slices: CategorySlice[]): string[] {
  const claimed = new Set(slices.map(reservedFillFor));
  const spare = Object.values(CATEGORY_FILL).filter((fill) => !claimed.has(fill));
  return [...CUSTOM_CATEGORY_FILLS, ...spare];
}

/** Stable hue per category name, every hue used at most once: two slices of one
 *  pie must never be indistinguishable. */
export function sliceFills(slices: CategorySlice[]): string[] {
  const pool = customFillPool(slices);
  const customNames = slices
    .map((slice) => slice.name)
    .filter((name) => !CATEGORY_FILL[name.toLowerCase()])
    .sort();
  return slices.map(
    (slice) => reservedFillFor(slice) ?? pool[customNames.indexOf(slice.name)]
  );
}

/** The rollup bucket declares what it swallowed, so simplification never hides money. */
export function categoryTooltipDetail(slice: CategorySlice, total: number): string {
  const figure = `${formatCurrency(slice.amount)} (${percentOfTotal(slice.amount, total)}%)`;
  if (slice.rolledUpNames.length === NO_CATEGORIES) return figure;
  return `${figure}${DETAIL_SEPARATOR}${slice.rolledUpNames.join(", ")}`;
}

/** One row per real category, never rolled up: the chart simplifies, the export does not. */
export function categoryMixCsvRows(
  categories: CategoryTotal[],
  labor: LaborCostSummary | null
): string[][] {
  const rows = toNamedAmounts(categories, labor);
  const total = rows.reduce((sum, row) => sum + parseFloat(row.amount), NO_MONEY);
  return [
    CSV_HEADER,
    ...rows.map((row) => [
      row.name,
      row.amount,
      percentOfTotal(parseFloat(row.amount), total),
    ]),
  ];
}

export function categoryMixKpi(grandTotal: string): string {
  return `${formatCurrency(grandTotal)} total cost`;
}

/**
 * A genuine part-to-whole capped at six slices — the narrow range in which a pie
 * is defensible — composed exactly like the shipped quote-conversion chart.
 */
export function CategoryMixChart({
  categories,
  labor,
}: {
  categories: CategoryTotal[];
  labor: LaborCostSummary | null;
}) {
  const slices = toCategorySlices(categories, labor);

  if (slices.length === NO_CATEGORIES) {
    return <ChartEmptyState heading={EMPTY_HEADING} body={EMPTY_BODY} />;
  }

  const fills = sliceFills(slices);
  const total = totalOf(slices);

  return (
    <div data-testid={CATEGORY_MIX_TEST_ID}>
      <ResponsiveContainer width="100%" height={CHART_HEIGHT}>
        <PieChart>
          <Pie
            data={slices}
            dataKey="amount"
            nameKey="name"
            cx="50%"
            cy="50%"
            outerRadius={OUTER_RADIUS}
            isAnimationActive={false}
            label={sliceLabel}
          >
            {slices.map((slice, index) => (
              <Cell key={slice.name} fill={fills[index]} />
            ))}
          </Pie>
          <Tooltip
            contentStyle={CHART_TOOLTIP_STYLE}
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            formatter={(_value: any, name: any, entry: any) => [
              categoryTooltipDetail(entry.payload as CategorySlice, total),
              name,
            ]}
          />
          <Legend wrapperStyle={CHART_TICK} />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
}

/** A slice under the threshold would collide with its neighbours; the legend and
 *  tooltip still identify it in full. */
function sliceLabel({ name, percent }: { name?: string; percent?: number }): string {
  const share = (percent ?? NO_MONEY) * PERCENT_MULTIPLIER;
  if (share < PIE_LABEL_MIN_PERCENT) return SUPPRESSED_LABEL;
  return `${name ?? SUPPRESSED_LABEL} ${share.toFixed(0)}%`;
}
