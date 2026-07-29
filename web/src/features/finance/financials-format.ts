/**
 * Pure display and geometry helpers for the financial dashboard. React-free and
 * unit-tested: every rendered figure still formats from its backend string, so
 * the only arithmetic here is chart geometry and the pie's category rollup.
 */

import {
  BUDGET_TIER_FILL,
  BUDGET_WARNING_PERCENT,
  BULLET_CHART_AXIS_PADDING,
  BULLET_ROW_HEIGHT,
  CHART_HEIGHT,
  LABEL_TRUNCATE_LENGTH,
  MAX_PIE_SLICES,
  OTHER_CATEGORY_NAME,
  PERCENT_AXIS_CLAMP,
  PERCENT_AXIS_FLOOR,
} from "@/components/shared/chart-theme";
import type { BudgetVsActual } from "./types";

const MONTH_NAMES = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const ABBREVIATION_LENGTH = 3;
const YEAR_SUFFIX_START = 2;
const FIRST_DAY_OF_MONTH = 1;
const LAST_POSSIBLE_DAY_OF_MONTH = 31;
const DOLLARS_PER_THOUSAND = 1000;
const AXIS_STEP = 10;
const ELLIPSIS = "…";
const NO_MONEY = 0;

/** Splits "YYYY-MM" rather than constructing a Date: a date-only string shifts a
 *  day — and therefore a month — across timezones. */
function monthParts(month: string): { name: string; year: string } | null {
  const [year, monthNumber] = month.split("-");
  const name = MONTH_NAMES[Number(monthNumber) - 1];
  return year && name ? { name, year } : null;
}

/** "2026-03" -> "Mar 26" — the dense axis tick. */
export function formatMonthLabel(month: string): string {
  const parts = monthParts(month);
  if (!parts) return month;
  return `${parts.name.slice(0, ABBREVIATION_LENGTH)} ${parts.year.slice(YEAR_SUFFIX_START)}`;
}

/** "2026-03" -> "March 2026" — the trend tooltip, where there is room to spell it. */
export function formatFullMonthLabel(month: string): string {
  const parts = monthParts(month);
  if (!parts) return month;
  return `${parts.name} ${parts.year}`;
}

/** Splits "YYYY-MM-DD" for the same reason monthParts splits "YYYY-MM": a
 *  date-only string shifts a day across timezones once a Date is constructed. */
function dayParts(
  day: string
): { name: string; dayOfMonth: number; year: string } | null {
  const [year, monthNumber, dayNumber] = day.split("-");
  const name = MONTH_NAMES[Number(monthNumber) - 1];
  const dayOfMonth = Number(dayNumber);
  const isRealDay =
    Number.isInteger(dayOfMonth) &&
    dayOfMonth >= FIRST_DAY_OF_MONTH &&
    dayOfMonth <= LAST_POSSIBLE_DAY_OF_MONTH;
  return year && name && isRealDay ? { name, dayOfMonth, year } : null;
}

/** "2026-07-29" -> "Jul 29, 2026". The day is never zero-padded, and an
 *  unparseable string comes back unchanged rather than as a wrong date. */
export function formatFindingDate(day: string): string {
  const parts = dayParts(day);
  if (!parts) return day;
  return `${parts.name.slice(0, ABBREVIATION_LENGTH)} ${parts.dayOfMonth}, ${parts.year}`;
}

/** 12000 -> "$12k", -4000 -> "-$4k". The sign leads the symbol, matching
 *  formatSignedCurrency — a value axis reading "$-4k" is wrong on a finance surface. */
export function formatAxisThousands(value: number): string {
  const sign = value < NO_MONEY ? "-" : "";
  const thousands = Math.abs(value) / DOLLARS_PER_THOUSAND;
  return `${sign}$${thousands.toFixed(0)}k`;
}

/** Caps a category-axis label at the axis width. The full name stays recoverable
 *  from the tooltip and the CSV. */
export function truncateLabel(name: string): string {
  if (name.length <= LABEL_TRUNCATE_LENGTH) return name;
  return name.slice(0, LABEL_TRUNCATE_LENGTH - ELLIPSIS.length) + ELLIPSIS;
}

/** Bar geometry only — the true percent still renders in the overflow label,
 *  tooltip, attention list, table and CSV. */
export function clampPercentForAxis(percentUsed: string): number {
  return Math.min(PERCENT_AXIS_CLAMP, parseFloat(percentUsed));
}

/** Floor keeps the 100% reference line on screen; clamp stops one extreme
 *  overrun from collapsing every other bar into a stub. */
export function axisMaxDomain(highestPercentUsed: number): number {
  const roundedUp = Math.ceil(highestPercentUsed / AXIS_STEP) * AXIS_STEP;
  return Math.min(PERCENT_AXIS_CLAMP, Math.max(PERCENT_AXIS_FLOOR, roundedUp));
}

/** The warning band needs money left over, not just a high percent: a budget
 *  spent to exactly 100% is at its boundary, not "nearing" it. */
export function budgetTierFill(
  budget: Pick<BudgetVsActual, "percentUsed" | "remaining">
): string {
  const remaining = parseFloat(budget.remaining);
  if (remaining < NO_MONEY) return BUDGET_TIER_FILL.over;
  const percentUsed = parseFloat(budget.percentUsed);
  if (percentUsed >= BUDGET_WARNING_PERCENT && remaining > NO_MONEY) {
    return BUDGET_TIER_FILL.warning;
  }
  return BUDGET_TIER_FILL.normal;
}

/** Plot height grows linearly with the row count and has deliberately no ceiling:
 *  a cap would compress rows below the legible floor. The viewport scrolls instead. */
export function bulletChartHeight(rowCount: number): number {
  return Math.max(CHART_HEIGHT, rowCount * BULLET_ROW_HEIGHT + BULLET_CHART_AXIS_PADDING);
}

export interface CategoryAmount {
  name: string;
  amount: number;
}

export interface CategorySlice extends CategoryAmount {
  /** Names folded into this slice. Empty except on the rollup bucket. */
  rolledUpNames: string[];
}

/** Caps the pie at MAX_PIE_SLICES by folding the smallest categories into Other,
 *  which keeps the nominal ramp free of repeated hues. The CSV stays unrolled. */
export function rollUpCategories(rows: CategoryAmount[]): CategorySlice[] {
  const named = rows
    .filter((row) => row.name !== OTHER_CATEGORY_NAME)
    .sort(byAmountDescending);
  const existingOther = rows.find((row) => row.name === OTHER_CATEGORY_NAME);
  const sliceCount = named.length + (existingOther ? 1 : 0);

  if (sliceCount <= MAX_PIE_SLICES) {
    const withinCap = existingOther ? [...named, existingOther] : named;
    return withinCap.map(toSlice);
  }

  const keptCount = MAX_PIE_SLICES - 1;
  const rolled = named.slice(keptCount);
  return [...named.slice(0, keptCount).map(toSlice), buildOtherSlice(rolled, existingOther)];
}

function byAmountDescending(left: CategoryAmount, right: CategoryAmount): number {
  return right.amount - left.amount;
}

function toSlice(row: CategoryAmount): CategorySlice {
  return { ...row, rolledUpNames: [] };
}

/** Other always sorts last, however large it grows — the rollup bucket must never
 *  read as a first-class category. */
function buildOtherSlice(
  rolled: CategoryAmount[],
  existingOther: CategoryAmount | undefined
): CategorySlice {
  const rolledTotal = rolled.reduce((sum, row) => sum + row.amount, NO_MONEY);
  return {
    name: OTHER_CATEGORY_NAME,
    amount: (existingOther?.amount ?? NO_MONEY) + rolledTotal,
    rolledUpNames: rolled.map((row) => row.name),
  };
}
