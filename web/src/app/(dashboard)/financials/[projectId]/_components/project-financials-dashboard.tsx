"use client";

import Link from "next/link";
import { useState } from "react";

import { FinanceSummaryTiles } from "@/app/(dashboard)/financials/_components/finance-summary-tiles";
import { FinancialsSkeleton } from "@/app/(dashboard)/financials/_components/financials-skeleton";
import { StatusBadge } from "@/components/shared/status-badge";
import { useProjectFinancials, useProjectMarginTrend } from "@/features/finance/hooks";
import { DEFAULT_TREND_WINDOW, type TrendWindow } from "@/features/finance/types";
import { ApiError } from "@/lib/api-client";

const NOT_FOUND_STATUS = 404;
const FINANCIALS_PATH = "/financials";

const LOAD_ERROR_MESSAGE = "Couldn't load financials. Refresh to try again.";
const NOT_FOUND_MESSAGE = "Project not found.";
const BACK_LINK_LABEL = "← Financials";
const BACK_LINK_ARIA_LABEL = "Back to Financials";
const SUBTITLE = "Margin, budget and cost detail.";
const REVENUE_TILE_TITLE = "Revenue";
const COST_TILE_TITLE = "Cost";
const MARGIN_TILE_TITLE = "Margin";
const PROJECT_TEST_ID_PREFIX = "project";

const ERROR_PANEL_CLASS =
  "rounded-xl border border-red-200 bg-red-50 px-6 py-12 text-center text-sm font-medium text-red-800";
const NOT_FOUND_PANEL_CLASS =
  "rounded-xl border border-border bg-card px-6 py-12 text-center text-sm text-muted-foreground";
const LINK_CLASS = "text-sm text-brand hover:underline";

/** A wrong tenant, a soft-deleted project and a bad id all arrive as one status
 *  code — read it, never match on the message text. */
export function isNotFoundError(error: unknown): boolean {
  return error instanceof ApiError && error.status === NOT_FOUND_STATUS;
}

/**
 * The only hook-owning component on `/financials/[projectId]`.
 *
 * Two queries, two keys: the trend window belongs to the trend alone, so
 * switching it can never restate the lifetime tiles beside it (D-10).
 */
export default function ProjectFinancialsDashboard({
  projectId,
}: {
  projectId: string;
}) {
  const [trendWindow, setTrendWindow] = useState<TrendWindow>(DEFAULT_TREND_WINDOW);
  const financials = useProjectFinancials(projectId);
  const trend = useProjectMarginTrend(projectId, trendWindow);

  if (financials.isLoading || trend.isLoading) {
    return <FinancialsSkeleton variant="project" />;
  }
  if (isNotFoundError(financials.error)) return <ProjectNotFoundPanel />;
  if (financials.isError || !financials.data) return <LoadErrorPanel />;

  const { name, status, breakdown } = financials.data;

  return (
    <div className="space-y-6">
      <ProjectHeader name={name} status={status} />

      <FinanceSummaryTiles
        revenueTitle={REVENUE_TILE_TITLE}
        costTitle={COST_TILE_TITLE}
        marginTitle={MARGIN_TILE_TITLE}
        cost={breakdown.grandTotal}
        margin={breakdown.margin}
        testIdPrefix={PROJECT_TEST_ID_PREFIX}
      />
    </div>
  );
}

function ProjectHeader({ name, status }: { name: string; status: string }) {
  return (
    <div>
      <Link href={FINANCIALS_PATH} aria-label={BACK_LINK_ARIA_LABEL} className={LINK_CLASS}>
        {BACK_LINK_LABEL}
      </Link>
      <div className="mt-1 flex items-center gap-2">
        <h1 className="text-xl font-normal text-gray-900">{name}</h1>
        <StatusBadge status={status} />
      </div>
      <p className="text-sm text-muted-foreground">{SUBTITLE}</p>
    </div>
  );
}

/** A missing project is a routing outcome, not a failure: an inline panel with a
 *  way back, never a toast over an empty dashboard. */
function ProjectNotFoundPanel() {
  return (
    <div data-testid="project-financials-not-found" className={NOT_FOUND_PANEL_CLASS}>
      <p>{NOT_FOUND_MESSAGE}</p>
      <Link href={FINANCIALS_PATH} className={`mt-2 inline-block ${LINK_CLASS}`}>
        {BACK_LINK_ARIA_LABEL}
      </Link>
    </div>
  );
}

function LoadErrorPanel() {
  return (
    <div data-testid="financials-error" className={ERROR_PANEL_CLASS}>
      {LOAD_ERROR_MESSAGE}
    </div>
  );
}
