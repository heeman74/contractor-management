"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  LabelList,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import {
  BULLET_AXIS_WIDTH,
  BULLET_BAR_SIZE,
  BULLET_REFERENCE_STROKE,
  BULLET_VIEWPORT_MAX_CLASS,
  CHART_TICK,
  CHART_TOOLTIP_STYLE,
  INACTIVE_BAR_FILL_OPACITY,
  OVERFLOW_LABEL_FILL,
} from "@/components/shared/chart-theme";
import { formatMarginPercent } from "@/features/finance/components/MarginSummarySection";
import {
  axisMaxDomain,
  budgetTierFill,
  bulletChartHeight,
  truncateLabel,
} from "@/features/finance/financials-format";

/**
 * One row of a bullet display: how much of a budget is spent, against the same
 * 100% reference every other row is read against. Deliberately free of any
 * knowledge of what the row names — a budget anchors to more than one thing.
 */
export interface BulletBarRow {
  id: string;
  /** The full name. Truncation is a display concern of the axis, not of the data. */
  label: string;
  /** True, unclamped, straight from the backend — the tooltip and label show this. */
  percentUsed: string;
  /** Drives the tier band with percentUsed: a budget spent to exactly 100% is not "nearing". */
  remaining: string;
  /** Bar geometry only, capped at the axis clamp. */
  percentUsedClamped: number;
  spentLabel: string;
  budgetLabel: string;
  statusLabel?: string;
  isInactive?: boolean;
  isOverClamp?: boolean;
}

const BUDGET_REFERENCE_PERCENT = 100;
const BUDGET_REFERENCE_LABEL = "Budget";
const CHART_LABEL_FONT_SIZE = 11;
const OVERFLOW_GLYPH = "▸";
const OVERFLOW_LABEL_GAP = 4;
const HALF = 2;
const TOOLTIP_DETAIL_SEPARATOR = " · ";
const FULL_FILL_OPACITY = 1;
const CHART_MARGIN = { top: 4, right: 48, bottom: 0, left: 0 };

interface BulletBarChartProps {
  rows: BulletBarRow[];
  /** Each surface names its own wrapper so one chart can serve several of them. */
  testId: string;
  /** Omitted where a row has no destination: no handler, default cursor. */
  onRowClick?: (id: string) => void;
}

/** Resolves whatever the axis handed back — full or truncated — to the full label. */
export function rowLabelFor(value: unknown, rows: BulletBarRow[]): string {
  const text = String(value);
  const match = rows.find(
    (row) => row.label === text || truncateLabel(row.label) === text
  );
  return match ? match.label : text;
}

function percentLabel(percentUsed: string): string {
  return `${formatMarginPercent(percentUsed)}%`;
}

function tooltipDetail(row: BulletBarRow): string {
  const spend = `${row.spentLabel} of ${row.budgetLabel}${TOOLTIP_DETAIL_SEPARATOR}${percentLabel(row.percentUsed)}`;
  return row.statusLabel ? `${spend}${TOOLTIP_DETAIL_SEPARATOR}${row.statusLabel}` : spend;
}

/**
 * Horizontal bullet bars: percent-of-budget on a common scale, so a small budget
 * and a large one stay comparable. Dollars live in the tooltip and the CSV.
 */
export function BulletBarChart({ rows, testId, onRowClick }: BulletBarChartProps) {
  const highestPercent = Math.max(...rows.map((row) => row.percentUsedClamped));

  return (
    <div className={BULLET_VIEWPORT_MAX_CLASS} data-testid={testId}>
      <ResponsiveContainer width="100%" height={bulletChartHeight(rows.length)}>
        <BarChart data={rows} layout="vertical" margin={CHART_MARGIN} accessibilityLayer>
          <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
          <XAxis
            type="number"
            domain={[0, axisMaxDomain(highestPercent)]}
            tickFormatter={(value) => `${value}%`}
            tick={CHART_TICK}
            tickLine={false}
            axisLine={false}
          />
          <YAxis
            type="category"
            dataKey="label"
            width={BULLET_AXIS_WIDTH}
            interval={0}
            tick={CHART_TICK}
            tickLine={false}
            axisLine={false}
            tickFormatter={truncateLabel}
          />
          <ReferenceLine
            x={BUDGET_REFERENCE_PERCENT}
            stroke={BULLET_REFERENCE_STROKE}
            strokeDasharray="3 3"
            label={{
              value: BUDGET_REFERENCE_LABEL,
              position: "top",
              fontSize: CHART_LABEL_FONT_SIZE,
            }}
          />
          <Tooltip
            contentStyle={CHART_TOOLTIP_STYLE}
            labelFormatter={(value) => rowLabelFor(value, rows)}
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            formatter={(_value: any, _name: any, entry: any) => [
              tooltipDetail(entry.payload as BulletBarRow),
              "",
            ]}
          />
          <Bar
            dataKey="percentUsedClamped"
            barSize={BULLET_BAR_SIZE}
            isAnimationActive={false}
            cursor={onRowClick ? "pointer" : undefined}
            onClick={
              onRowClick
                ? // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  (bar: any) => onRowClick((bar.payload as BulletBarRow).id)
                : undefined
            }
          >
            {rows.map((row) => (
              <Cell
                key={row.id}
                fill={budgetTierFill(row)}
                fillOpacity={row.isInactive ? INACTIVE_BAR_FILL_OPACITY : FULL_FILL_OPACITY}
              />
            ))}
            <LabelList
              dataKey="percentUsedClamped"
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              content={(labelProps: any) => (
                <OverflowLabel
                  row={rows[labelProps.index as number]}
                  x={Number(labelProps.x)}
                  y={Number(labelProps.y)}
                  width={Number(labelProps.width)}
                  height={Number(labelProps.height)}
                />
              )}
            />
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

/**
 * A clamped bar carries the glyph and its real number, so truncation declares
 * itself: a bar at the axis edge can never be misread as "exactly at the clamp".
 */
function OverflowLabel({
  row,
  x,
  y,
  width,
  height,
}: {
  row: BulletBarRow | undefined;
  x: number;
  y: number;
  width: number;
  height: number;
}) {
  if (!row?.isOverClamp) return null;
  return (
    <text
      data-testid={`budget-bar-overflow-${row.id}`}
      x={x + width + OVERFLOW_LABEL_GAP}
      y={y + height / HALF}
      fill={OVERFLOW_LABEL_FILL}
      fontSize={CHART_LABEL_FONT_SIZE}
      dominantBaseline="middle"
    >
      {`${OVERFLOW_GLYPH} ${percentLabel(row.percentUsed)}`}
    </text>
  );
}
