"use client";

import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { ChartEmptyState } from "@/components/shared/chart-empty-state";
import {
  BREAK_EVEN_STROKE,
  CHART_HEIGHT,
  CHART_TICK,
  CHART_TOOLTIP_STYLE,
  TREND_SERIES,
} from "@/components/shared/chart-theme";
import {
  NO_REVENUE_NOTE,
  formatMarginDollars,
  formatMarginPercent,
} from "@/features/finance/components/MarginSummarySection";
import {
  formatAxisThousands,
  formatFullMonthLabel,
  formatMonthLabel,
} from "@/features/finance/financials-format";
import type { RevenueBasis, TrendBucket } from "@/features/finance/types";
import { formatCurrency } from "@/lib/format";

export const TREND_TITLE = "Margin Trend";
export const TREND_CSV_FILENAME = "margin-trend.csv";
export const TREND_CHART_TEST_ID = "margin-trend-chart";

const EMPTY_HEADING = "No dated financial records yet";
const EMPTY_BODY =
  "Costs, tracked time, invoices and approved quotes appear here once they carry dates.";
const BREAK_EVEN_LABEL = "Break-even";
const CSV_HEADER = ["Month", "Revenue", "Cost", "Margin", "Margin %", "Revenue basis"];
/** A null month exports as an absent cell. A zero would fabricate a break-even. */
const EMPTY_CELL = "";
const ABSENT_FIGURE = "—";
const SERIES_NAMES = { revenue: "Revenue", cost: "Cost", margin: "Margin" } as const;
/** Bases whose figure is an estimate, so the tooltip names them where they occur. */
const ESTIMATED_BASES: readonly RevenueBasis[] = ["quoted", "mixed"];
const NO_REVENUE_BASIS: RevenueBasis = "none";

const BREAK_EVEN_VALUE = 0;
const NO_BUCKETS = 0;
const SINGLE_MONTH = 1;
const CHART_LABEL_FONT_SIZE = 11;
const TICK_MIN_GAP = 24;
/** Marks shared by all three series — the hierarchy lives in TREND_SERIES alone. */
const LINE_MARKS = {
  dot: false,
  activeDot: { r: 4 },
  isAnimationActive: false,
} as const;
const CHART_MARGIN = { top: 4, right: 8, bottom: 0, left: 0 };
const REFETCHING_CLASS = "opacity-60";
const DETAIL_SEPARATOR = " · ";
const CAPTION_CLASS = "mt-2 text-xs text-gray-500";

/** One month of the plot. Every series carries both the number the geometry needs
 *  and the backend string every rendered figure formats from. */
export interface TrendDatum {
  month: string;
  margin: number | null;
  revenue: number | null;
  cost: number;
  revenueBasis: RevenueBasis;
  marginLabel: string | null;
  revenueLabel: string | null;
  costLabel: string;
  marginPercentLabel: string | null;
}

/** The one place a trend money string becomes a number. A null stays null so the
 *  line renders a real gap rather than a fabricated break-even month. */
export function toTrendData(buckets: TrendBucket[]): TrendDatum[] {
  const asNumber = (value: string | null) => (value === null ? null : parseFloat(value));
  return buckets.map((bucket) => ({
    month: bucket.month,
    margin: asNumber(bucket.margin.margin),
    revenue: asNumber(bucket.margin.revenue),
    cost: parseFloat(bucket.cost),
    revenueBasis: bucket.margin.revenueBasis,
    ...trendLabels(bucket),
  }));
}

function trendLabels(bucket: TrendBucket) {
  const { margin } = bucket;
  return {
    marginLabel: margin.margin === null ? null : formatMarginDollars(margin.margin),
    revenueLabel: margin.revenue === null ? null : formatCurrency(margin.revenue),
    costLabel: formatCurrency(bucket.cost),
    marginPercentLabel:
      margin.marginPercent === null
        ? null
        : `${formatMarginPercent(margin.marginPercent)}%`,
  };
}

/** Empty cells for nulls: the export never invents a figure the backend withheld. */
export function trendCsvRows(buckets: TrendBucket[]): string[][] {
  return [
    CSV_HEADER,
    ...buckets.map((bucket) => [
      bucket.month,
      bucket.margin.revenue ?? EMPTY_CELL,
      bucket.cost,
      bucket.margin.margin ?? EMPTY_CELL,
      bucket.margin.marginPercent ?? EMPTY_CELL,
      bucket.margin.revenueBasis,
    ]),
  ];
}

export function trendMonthsKpi(buckets: TrendBucket[]): string {
  return buckets.length === SINGLE_MONTH ? "1 month" : `${buckets.length} months`;
}

function hasNoRevenueAnywhere(buckets: TrendBucket[]): boolean {
  return buckets.every((bucket) => bucket.margin.revenueBasis === NO_REVENUE_BASIS);
}

/** The tooltip names an estimated basis where it happens, so the quote→invoice
 *  step-down reads as a basis change rather than as lost revenue. */
export function trendTooltipLabel(month: string, data: TrendDatum[]): string {
  const datum = data.find((row) => row.month === month);
  const label = formatFullMonthLabel(month);
  if (datum && ESTIMATED_BASES.includes(datum.revenueBasis)) {
    return `${label}${DETAIL_SEPARATOR}${datum.revenueBasis}`;
  }
  return label;
}

function seriesFigure(datum: TrendDatum, dataKey: string): string {
  if (dataKey === "revenue") return datum.revenueLabel ?? ABSENT_FIGURE;
  if (dataKey === "cost") return datum.costLabel;
  const percent = datum.marginPercentLabel;
  const figure = datum.marginLabel ?? ABSENT_FIGURE;
  return percent === null ? figure : `${figure} (${percent})`;
}

/**
 * Three series on one dollar axis: margin is the focal line, revenue and cost are
 * the context that explains it. `connectNulls` is deliberately left at its false
 * default — a month with no margin must break the line, not cross break-even.
 */
export function MarginTrendChart({
  buckets,
  isRefetching,
}: {
  buckets: TrendBucket[];
  isRefetching: boolean;
}) {
  if (buckets.length === NO_BUCKETS) {
    return <ChartEmptyState heading={EMPTY_HEADING} body={EMPTY_BODY} />;
  }

  const data = toTrendData(buckets);

  return (
    <div
      data-testid={TREND_CHART_TEST_ID}
      className={isRefetching ? REFETCHING_CLASS : ""}
      aria-busy={isRefetching}
    >
      <ResponsiveContainer width="100%" height={CHART_HEIGHT}>
        <LineChart data={data} margin={CHART_MARGIN} accessibilityLayer>
          <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
          <XAxis
            dataKey="month"
            tickFormatter={formatMonthLabel}
            interval="preserveStartEnd"
            minTickGap={TICK_MIN_GAP}
            tick={CHART_TICK}
            tickLine={false}
          />
          <YAxis
            tickFormatter={formatAxisThousands}
            tick={CHART_TICK}
            tickLine={false}
            axisLine={false}
          />
          <ReferenceLine
            y={BREAK_EVEN_VALUE}
            stroke={BREAK_EVEN_STROKE}
            strokeDasharray="3 3"
            label={{
              value: BREAK_EVEN_LABEL,
              position: "insideTopLeft",
              fontSize: CHART_LABEL_FONT_SIZE,
            }}
          />
          <Tooltip
            contentStyle={CHART_TOOLTIP_STYLE}
            labelFormatter={(month) => trendTooltipLabel(String(month), data)}
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            formatter={(_value: any, name: any, entry: any) => [
              seriesFigure(entry.payload as TrendDatum, String(entry.dataKey)),
              name,
            ]}
          />
          <Legend wrapperStyle={CHART_TICK} />
          <Line
            type="monotone"
            dataKey="revenue"
            name={SERIES_NAMES.revenue}
            {...TREND_SERIES.revenue}
            {...LINE_MARKS}
          />
          <Line
            type="monotone"
            dataKey="cost"
            name={SERIES_NAMES.cost}
            {...TREND_SERIES.cost}
            {...LINE_MARKS}
          />
          <Line
            type="monotone"
            dataKey="margin"
            name={SERIES_NAMES.margin}
            {...TREND_SERIES.margin}
            {...LINE_MARKS}
          />
        </LineChart>
      </ResponsiveContainer>
      {hasNoRevenueAnywhere(buckets) && (
        <p data-testid="trend-no-revenue-note" className={CAPTION_CLASS}>
          {NO_REVENUE_NOTE}
        </p>
      )}
    </div>
  );
}
