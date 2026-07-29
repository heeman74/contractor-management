"use client";

import { Bot } from "lucide-react";

import { QUOTED_BASIS_CAPTION } from "@/app/(dashboard)/financials/_components/finance-summary-tiles";
import { ChartEmptyState } from "@/components/shared/chart-empty-state";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  UNBURDENED_BODY,
  UNBURDENED_TITLE,
} from "@/features/finance/components/CostBreakdownSummary";
import {
  FINANCE_ALERT_CHIP_CLASS,
  FINANCE_FLAG_CHIP_CLASS,
} from "@/features/finance/components/FinanceFlagChip";
import { formatFindingDate } from "@/features/finance/financials-format";
import type {
  FindingSeverity,
  ProfitabilityFinding,
  RevenueBasis,
} from "@/features/finance/types";

const CARD_TITLE = "Profitability Finding";
const CARD_ARIA_LABEL = "Profitability Finding card";
const SUGGESTED_ACTION_EYEBROW = "SUGGESTED ACTION";
/** SC3 stated to the user. The D-05 grounding validator is what makes it true. */
const DISCLOSURE =
  "AI-written from this project's recorded figures — every number is from your data, never an AI estimate.";
/** The shipped mixed caption names an estimated amount; the finding response
 *  carries none and must not fabricate one, so this is the amount-free sibling. */
const MIXED_BASIS_CAPTION = "Includes revenue from approved quotes — not yet invoiced.";
const EMPTY_HEADING = "No margin erosion flagged";
const EMPTY_BODY =
  "A nightly AI review posts a finding here when this project's margin starts to slip.";
const INCOMPLETE_EMPTY_HEADING = "Not analyzed — incomplete cost data";
const INCOMPLETE_EMPTY_BODY =
  "AI skips projects with missing or unrated costs, so a finding can never rest on understated numbers.";
const ERROR_MESSAGE = "Couldn't load the profitability finding. Refresh to try again.";

const FOUND_TEMPLATE = (found: string) => `Found ${found}`;
const FOUND_AND_CONFIRMED_TEMPLATE = (found: string, confirmed: string) =>
  `Found ${found} · Last confirmed ${confirmed}`;

/** One map per concept: a band's copy and its color can never drift apart. */
const SEVERITY_CHIP: Record<FindingSeverity, { label: string; className: string }> = {
  warning: { label: "Margin warning", className: FINANCE_FLAG_CHIP_CLASS },
  critical: { label: "Margin critical", className: FINANCE_ALERT_CHIP_CLASS },
};

interface ProfitabilityFindingCardProps {
  finding: ProfitabilityFinding | null;
  isLoading: boolean;
  isError: boolean;
  /** The project's own incomplete-cost flag, already on the page. Selects the
   *  honesty empty state so a skipped project never reads as an all-clear. */
  incompleteCostData: boolean;
}

/** A finding restated for a week is a different fact from one found last night,
 *  so both dates render whenever they differ. */
export function findingDateLine(finding: ProfitabilityFinding): string {
  const found = formatFindingDate(finding.foundOn);
  if (finding.lastConfirmedOn === finding.foundOn) return FOUND_TEMPLATE(found);
  return FOUND_AND_CONFIRMED_TEMPLATE(found, formatFindingDate(finding.lastConfirmedOn));
}

/** An invoiced basis has nothing to qualify, so nothing is said. */
export function revenueBasisCaption(basis: RevenueBasis): string | null {
  if (basis === "quoted") return QUOTED_BASIS_CAPTION;
  if (basis === "mixed") return MIXED_BASIS_CAPTION;
  return null;
}

/** The honesty variant says WHY the AI was silent instead of implying an all-clear. */
export function emptyStateCopy(incompleteCostData: boolean): {
  heading: string;
  body: string;
} {
  if (incompleteCostData) {
    return { heading: INCOMPLETE_EMPTY_HEADING, body: INCOMPLETE_EMPTY_BODY };
  }
  return { heading: EMPTY_HEADING, body: EMPTY_BODY };
}

/**
 * The latest open AI profitability finding (D-08).
 *
 * Presentational only: it never fetches, never branches on permissions and holds
 * no state. Loading / error / empty / present is decided by the dashboard above it.
 *
 * Card chrome never changes with severity — only the chip does — so a warning
 * finding can never be mistaken for the page-level error panel.
 */
export function ProfitabilityFindingCard({
  finding,
  isLoading,
  isError,
  incompleteCostData,
}: ProfitabilityFindingCardProps) {
  const showsFinding = !isLoading && !isError && finding !== null;

  return (
    <Card aria-label={CARD_ARIA_LABEL} data-testid="profitability-finding">
      <CardContent className="pt-4">
        <div className="flex items-start justify-between gap-2">
          <div className="flex items-start gap-2">
            <div className="rounded-md bg-secondary p-2">
              <Bot className="h-4 w-4 text-foreground/70" />
            </div>
            <p className="text-sm text-gray-500">{CARD_TITLE}</p>
          </div>
          {showsFinding && <SeverityChip severity={finding.severity} />}
        </div>

        <FindingCardBody
          finding={finding}
          isLoading={isLoading}
          isError={isError}
          incompleteCostData={incompleteCostData}
        />
      </CardContent>
    </Card>
  );
}

function FindingCardBody({
  finding,
  isLoading,
  isError,
  incompleteCostData,
}: ProfitabilityFindingCardProps) {
  if (isLoading) return <FindingSkeleton />;
  if (isError) return <FindingError />;
  if (finding === null) return <FindingEmptyState incompleteCostData={incompleteCostData} />;
  return <FindingDetail finding={finding} />;
}

function SeverityChip({ severity }: { severity: FindingSeverity }) {
  const chip = SEVERITY_CHIP[severity];
  return (
    <span data-testid="profitability-finding-severity" className={chip.className}>
      {chip.label}
    </span>
  );
}

function FindingSkeleton() {
  return (
    <div data-testid="profitability-finding-skeleton" className="mt-4">
      <Skeleton className="h-4 w-full" />
      <Skeleton className="mt-2 h-4 w-2/3" />
    </div>
  );
}

/** Scoped to the card, with no nested panel chrome: a findings outage must read
 *  as one card failing, never as the money dashboard failing. */
function FindingError() {
  return (
    <p
      data-testid="profitability-finding-error"
      className="py-8 text-center text-sm font-medium text-red-800"
    >
      {ERROR_MESSAGE}
    </p>
  );
}

function FindingEmptyState({ incompleteCostData }: { incompleteCostData: boolean }) {
  const { heading, body } = emptyStateCopy(incompleteCostData);
  return (
    <div data-testid="profitability-finding-empty">
      <ChartEmptyState heading={heading} body={body} />
    </div>
  );
}

/** The narrative and the action render verbatim — no truncation, no clamp, no
 *  "read more" — and no figure inside them is ever re-parsed or re-formatted. */
function FindingDetail({ finding }: { finding: ProfitabilityFinding }) {
  const basisCaption = revenueBasisCaption(finding.revenueBasis);

  return (
    <>
      <p data-testid="profitability-finding-date" className="mt-1 text-xs text-gray-500">
        {findingDateLine(finding)}
      </p>

      <p
        data-testid="profitability-finding-narrative"
        className="mt-4 text-sm text-gray-700"
      >
        {finding.narrative}
      </p>

      <div className="mt-4 rounded-lg bg-secondary p-4">
        <p className="text-xs font-semibold uppercase tracking-wide text-gray-700">
          {SUGGESTED_ACTION_EYEBROW}
        </p>
        <p
          data-testid="profitability-finding-action"
          className="mt-1 text-sm text-gray-900"
        >
          {finding.correctiveAction}
        </p>
      </div>

      <div className="mt-4 space-y-1 text-xs text-gray-500">
        {basisCaption && (
          <p data-testid="profitability-finding-basis-note">{basisCaption}</p>
        )}
        {finding.laborIncluded && (
          <p data-testid="profitability-finding-labor-note">
            {`${UNBURDENED_TITLE}: ${UNBURDENED_BODY}`}
          </p>
        )}
        <p data-testid="profitability-finding-disclosure">{DISCLOSURE}</p>
      </div>
    </>
  );
}
