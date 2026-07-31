"use client";

import { ChartEmptyState } from "@/components/shared/chart-empty-state";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  UNBURDENED_BODY,
  UNBURDENED_TITLE,
} from "@/features/finance/components/CostBreakdownSummary";
import { formatMarginPercent } from "@/features/finance/components/MarginSummarySection";
import type { ProjectQuoteVariance, QuoteVarianceTrade } from "@/features/finance/types";
import { formatSignedCurrency } from "@/lib/format";
import { LABOR_NOTE } from "./scope-budget-bars";

export const QUOTE_VARIANCE_TEST_ID = "project-quote-variance";
export const QUOTE_VARIANCE_TITLE = "Quoted vs Actual by Trade";
export const QUOTE_VARIANCE_CSV_FILENAME = "quoted-vs-actual-by-trade.csv";

const HEADER_CLASS = "text-xs font-semibold uppercase tracking-wide text-gray-500";
const TOTAL_TEST_ID = "project-quote-variance-total";
const LABOR_NOTE_TEST_ID = "project-quote-variance-labor-note";

const NOT_YET_INVOICED = "Not yet invoiced";
const EMPTY_HEADING = "No completed work to compare";
const EMPTY_BODY = "Quoted vs actual appears once a trade's work has been invoiced.";
const NO_INVOICED_WORK_KPI = "No invoiced work yet";
const MATCHED_QUOTED_KPI = "Matched quoted";

const CSV_HEADER = [
  "Trade scope",
  "Quoted (pre-tax)",
  "Actual cost",
  "Variance",
  "Variance percent",
];

const ZERO_VARIANCE = 0;
const NO_TRADES = 0;
const EMPTY_CELL = "";

// The size-based contrast rule (37-UI-SPEC "Color") permits this weight and
// size to carry the signal on its own — the smaller recipe elsewhere on this
// surface must not be copied here, since it does not clear the same ratio.
const OVER_QUOTED_CLASS = "text-red-800";
const OTHER_FIGURE_CLASS = "text-gray-900";

/** Strips a leading sign — the dollar sign and the row's own position already
 *  carry the direction, so a doubled sign would say it twice. */
function unsigned(value: string): string {
  return value.startsWith("-") ? value.slice(1) : value;
}

function isOverQuoted(variance: string): boolean {
  return parseFloat(variance) > ZERO_VARIANCE;
}

/** "{percent}% over quoted" / "{percent}% under quoted" / "Matched quoted" /
 *  "No invoiced work yet" — the ChartCard KPI slot, never colored. */
export function quoteVarianceKpi(total: QuoteVarianceTrade | null): string {
  if (!total || total.variance === null || total.variancePercent === null) {
    return NO_INVOICED_WORK_KPI;
  }
  if (parseFloat(total.variance) === ZERO_VARIANCE) return MATCHED_QUOTED_KPI;
  const percent = formatMarginPercent(unsigned(total.variancePercent));
  return isOverQuoted(total.variance) ? `${percent}% over quoted` : `${percent}% under quoted`;
}

function toCsvRow(trade: QuoteVarianceTrade): string[] {
  return [
    trade.label,
    trade.quoted ?? EMPTY_CELL,
    trade.actual ?? EMPTY_CELL,
    trade.variance ?? EMPTY_CELL,
    trade.variancePercent ?? EMPTY_CELL,
  ];
}

/** True, unrolled backend strings — an export never inherits the table's
 *  "Not yet invoiced" display simplification (the 35-03 rule). */
export function quoteVarianceCsvRows(variance: ProjectQuoteVariance | undefined): string[][] {
  if (!variance) return [CSV_HEADER];
  return [CSV_HEADER, ...variance.scopes.map(toCsvRow), toCsvRow(variance.total)];
}

function VarianceFigure({ variance, percent }: { variance: string; percent: string | null }) {
  const pct = percent ? formatMarginPercent(unsigned(percent)) : null;
  return (
    <span className={isOverQuoted(variance) ? OVER_QUOTED_CLASS : OTHER_FIGURE_CLASS}>
      {formatSignedCurrency(variance)}
      {pct !== null && ` · ${pct}%`}
    </span>
  );
}

function QuoteVarianceRow({ trade, isTotal }: { trade: QuoteVarianceTrade; isTotal?: boolean }) {
  return (
    <TableRow
      data-testid={isTotal ? TOTAL_TEST_ID : undefined}
      className={isTotal ? "border-t" : undefined}
    >
      <TableCell className={isTotal ? "font-semibold text-gray-900" : "text-gray-700"}>
        {trade.label}
      </TableCell>
      <TableCell className="text-right text-gray-900">
        {trade.quoted !== null ? formatSignedCurrency(trade.quoted) : NOT_YET_INVOICED}
      </TableCell>
      <TableCell className="text-right text-gray-900">
        {trade.actual !== null ? formatSignedCurrency(trade.actual) : NOT_YET_INVOICED}
      </TableCell>
      <TableCell className="text-right">
        {trade.actual === null || trade.variance === null ? (
          <span className="text-gray-500">{NOT_YET_INVOICED}</span>
        ) : (
          <VarianceFigure variance={trade.variance} percent={trade.variancePercent} />
        )}
      </TableCell>
    </TableRow>
  );
}

/**
 * The drill-down's per-trade quoted-vs-actual table (FINAI-05). No green, no
 * check glyph, no "on target" chip and no band chip on variance: the sign, the
 * ink and the row label already carry the whole signal, so a fourth chip
 * family on a surface already carrying three confidence bands would dilute
 * all of them.
 */
export function QuoteVarianceTable({ variance }: { variance: ProjectQuoteVariance }) {
  if (variance.scopes.length === NO_TRADES) {
    return <ChartEmptyState heading={EMPTY_HEADING} body={EMPTY_BODY} />;
  }

  return (
    <div data-testid={QUOTE_VARIANCE_TEST_ID}>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead className={HEADER_CLASS}>Trade scope</TableHead>
            <TableHead className={`${HEADER_CLASS} text-right`}>Quoted</TableHead>
            <TableHead className={`${HEADER_CLASS} text-right`}>Actual</TableHead>
            <TableHead className={`${HEADER_CLASS} text-right`}>Variance</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {variance.scopes.map((trade) => (
            <QuoteVarianceRow key={trade.label} trade={trade} />
          ))}
          <QuoteVarianceRow trade={variance.total} isTotal />
        </TableBody>
      </Table>
      {variance.hasScopeAnchoredRows && (
        <p data-testid="scope-labor-note" className="mt-2 text-xs text-gray-500">
          {LABOR_NOTE}
        </p>
      )}
      {variance.laborIncluded && (
        <p data-testid={LABOR_NOTE_TEST_ID} className="mt-2 text-xs text-gray-500">
          {`${UNBURDENED_TITLE}: ${UNBURDENED_BODY}`}
        </p>
      )}
    </div>
  );
}
