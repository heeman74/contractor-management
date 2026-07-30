"use client";

import { Scale } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import {
  UNBURDENED_BODY,
  UNBURDENED_TITLE,
} from "@/features/finance/components/CostBreakdownSummary";
import { LABOR_NOTE } from "@/app/(dashboard)/financials/[projectId]/_components/scope-budget-bars";
import { formatSignedCurrency } from "@/lib/format";
import { formatMarginPercent } from "@/features/finance/components/MarginSummarySection";
import type { QuoteVariance, QuoteVarianceTrade } from "@/features/finance/types";

const CARD_TITLE = "Quoted vs Actual";
const CARD_ARIA_LABEL = "Quoted vs Actual card";
const QUOTED_LABEL = "Quoted (pre-tax)";
const ACTUAL_LABEL = "Actual cost";
const VARIANCE_LABEL = "Variance";
const PROJECT_TOTAL_LABEL = "Project total";
const NOT_YET_INVOICED = "Not yet invoiced";
const EMPTY_HEADING = "Not comparable yet";
const EMPTY_BODY =
  "Quoted vs actual appears once the work from this quote has been invoiced.";
const ERROR_MESSAGE = "Couldn't load quoted vs actual. Refresh to try again.";

const ZERO_VARIANCE = 0;
const FIGURE_TEST_ID = "quote-variance-figure";
const INTERPRETATION_TEST_ID = "quote-variance-interpretation";
const EMPTY_TEST_ID = "quote-variance-empty";
const ERROR_TEST_ID = "quote-variance-error";
const SKELETON_TEST_ID = "quote-variance-skeleton";
const LABOR_NOTE_TEST_ID = "quote-variance-labor-note";

const NEGATIVE_FIGURE_CLASS = "text-sm font-semibold text-red-800";
const NON_NEGATIVE_FIGURE_CLASS = "text-sm font-semibold text-gray-900";

interface QuoteVarianceCardProps {
  variance: QuoteVariance | undefined;
  isLoading: boolean;
  isError: boolean;
}

/** Positive means the work cost more than it was quoted for (the sign
 *  convention `variance = actual - quoted`, negated margin percent). */
function isOverQuoted(variance: string): boolean {
  return parseFloat(variance) > ZERO_VARIANCE;
}

function isExactlyMatched(variance: string): boolean {
  return parseFloat(variance) === ZERO_VARIANCE;
}

/** Strips a leading sign for the unsigned half of the interpretation sentence
 *  and the compact figure's percent — the direction is already carried by the
 *  dollar sign and by "above"/"below" in the sentence, never by a doubled sign. */
function unsigned(value: string): string {
  return value.startsWith("-") ? value.slice(1) : value;
}

function varianceInterpretation(variance: string, percent: string | null): string {
  if (isExactlyMatched(variance)) {
    return "Actual cost matched this quote's pre-tax price.";
  }
  const amount = `$${unsigned(variance)}`;
  const pct = percent ? formatMarginPercent(unsigned(percent)) : "0";
  return isOverQuoted(variance)
    ? `Actual cost ran ${amount} (${pct}%) above this quote's pre-tax price.`
    : `Actual cost came in ${amount} (${pct}%) below this quote's pre-tax price.`;
}

/** The one place the variance figure is rendered — reused by the simple layout
 *  and by every row of the project-level table, so `FIGURE_TEST_ID` and the red
 *  rule can never drift between the two shapes. */
function VarianceFigure({
  variance,
  percent,
  testId,
}: {
  variance: string;
  percent: string | null;
  testId?: string;
}) {
  const pct = percent ? formatMarginPercent(unsigned(percent)) : null;
  return (
    <span
      data-testid={testId}
      className={isOverQuoted(variance) ? NEGATIVE_FIGURE_CLASS : NON_NEGATIVE_FIGURE_CLASS}
    >
      {formatSignedCurrency(variance)}
      {pct !== null && ` · ${pct}%`}
    </span>
  );
}

function VarianceInterpretationLine({
  variance,
  percent,
}: {
  variance: string | null;
  percent: string | null;
}) {
  if (variance === null) return null;
  return (
    <p data-testid={INTERPRETATION_TEST_ID} className="mt-1 text-xs text-gray-500">
      {varianceInterpretation(variance, percent)}
    </p>
  );
}

function CaptionStack({
  scopeAnchored,
  laborIncluded,
}: {
  scopeAnchored: boolean;
  laborIncluded: boolean;
}) {
  if (!scopeAnchored && !laborIncluded) return null;
  return (
    <div className="mt-4 space-y-1 text-xs text-gray-500">
      {scopeAnchored && <p data-testid="scope-labor-note">{LABOR_NOTE}</p>}
      {laborIncluded && (
        <p data-testid={LABOR_NOTE_TEST_ID}>{`${UNBURDENED_TITLE}: ${UNBURDENED_BODY}`}</p>
      )}
    </div>
  );
}

function EmptyState() {
  return (
    <div data-testid={EMPTY_TEST_ID}>
      <p className="text-sm font-medium text-muted-foreground">{EMPTY_HEADING}</p>
      <p className="mt-1 text-xs text-gray-500">{EMPTY_BODY}</p>
    </div>
  );
}

function ErrorState() {
  return (
    <p data-testid={ERROR_TEST_ID} className="py-8 text-center text-sm font-medium text-red-800">
      {ERROR_MESSAGE}
    </p>
  );
}

function VarianceSkeleton() {
  return (
    <div data-testid={SKELETON_TEST_ID}>
      <Skeleton className="h-4 w-full" />
      <Skeleton className="mt-2 h-4 w-2/3" />
    </div>
  );
}

function SimpleVarianceRows({ variance }: { variance: QuoteVariance }) {
  if (variance.quoted === null || variance.actual === null) return <EmptyState />;
  return (
    <>
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-500">{QUOTED_LABEL}</span>
        <span className="text-gray-900">{formatSignedCurrency(variance.quoted)}</span>
      </div>
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-500">{ACTUAL_LABEL}</span>
        <span className="text-gray-900">{formatSignedCurrency(variance.actual)}</span>
      </div>
      <Separator />
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-500">{VARIANCE_LABEL}</span>
        {variance.variance !== null && (
          <VarianceFigure
            variance={variance.variance}
            percent={variance.variancePercent}
            testId={FIGURE_TEST_ID}
          />
        )}
      </div>
      <VarianceInterpretationLine
        variance={variance.variance}
        percent={variance.variancePercent}
      />
    </>
  );
}

function ProjectVarianceRow({
  trade,
  isTotal,
  figureTestId,
}: {
  trade: QuoteVarianceTrade;
  isTotal?: boolean;
  figureTestId?: string;
}) {
  return (
    <div className="space-y-0.5">
      <div className="flex items-center justify-between text-sm">
        <span className={isTotal ? "font-semibold text-gray-900" : "text-gray-700"}>
          {trade.label}
        </span>
        <span className="text-gray-900">
          {trade.quoted !== null ? formatSignedCurrency(trade.quoted) : NOT_YET_INVOICED}
        </span>
      </div>
      <div className="flex items-center justify-between text-xs">
        <span className="text-gray-500">{VARIANCE_LABEL}</span>
        {trade.actual === null || trade.variance === null ? (
          <span className="text-gray-500">{NOT_YET_INVOICED}</span>
        ) : (
          <VarianceFigure
            variance={trade.variance}
            percent={trade.variancePercent}
            testId={figureTestId}
          />
        )}
      </div>
    </div>
  );
}

function ProjectVarianceTable({ variance }: { variance: QuoteVariance }) {
  const totalRow: QuoteVarianceTrade = {
    label: PROJECT_TOTAL_LABEL,
    quoted: variance.quoted,
    actual: variance.actual,
    variance: variance.variance,
    variancePercent: variance.variancePercent,
  };
  return (
    <div className="space-y-3">
      {variance.trades.map((trade) => (
        <ProjectVarianceRow key={trade.label} trade={trade} />
      ))}
      <Separator />
      <ProjectVarianceRow trade={totalRow} isTotal figureTestId={FIGURE_TEST_ID} />
      <VarianceInterpretationLine
        variance={variance.variance}
        percent={variance.variancePercent}
      />
    </div>
  );
}

const NO_TRADES = 0;

function CardBody({ variance, isLoading, isError }: QuoteVarianceCardProps) {
  if (isLoading) return <VarianceSkeleton />;
  if (isError) return <ErrorState />;
  if (!variance) return null;

  return (
    <>
      {variance.trades.length > NO_TRADES ? (
        <ProjectVarianceTable variance={variance} />
      ) : (
        <SimpleVarianceRows variance={variance} />
      )}
      <CaptionStack scopeAnchored={variance.scopeAnchored} laborIncluded={variance.laborIncluded} />
    </>
  );
}

/**
 * Presentational only — never fetches, holds no state. `QuoteVarianceSection`
 * owns the hook and passes down its result. Renders nothing at all (not even
 * the card chrome) when there is no result and nothing is loading or erroring —
 * that is the "not approved" state, where `useQuoteVariance` never runs at all
 * because variance is meaningless before an anchor exists.
 */
export function QuoteVarianceCard({ variance, isLoading, isError }: QuoteVarianceCardProps) {
  const hasNoResult = !isLoading && !isError && !variance;
  if (hasNoResult) return null;

  return (
    <Card aria-label={CARD_ARIA_LABEL} data-testid="quote-variance">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <span className="rounded-md bg-secondary p-2">
            <Scale className="h-4 w-4 text-foreground/70" />
          </span>
          {CARD_TITLE}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <CardBody variance={variance} isLoading={isLoading} isError={isError} />
      </CardContent>
    </Card>
  );
}
