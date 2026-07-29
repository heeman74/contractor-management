"use client";

import Link from "next/link";
import { useState } from "react";
import { Gauge, PieChart as PieChartIcon, TrendingUp } from "lucide-react";

import { ChartCard } from "@/app/(dashboard)/reports/_components/chart-card";
import { FinanceSummaryTiles } from "@/app/(dashboard)/financials/_components/finance-summary-tiles";
import { FinancialsSkeleton } from "@/app/(dashboard)/financials/_components/financials-skeleton";
import { StatusBadge } from "@/components/shared/status-badge";
import {
  useProjectFinancials,
  useProjectMarginTrend,
  useProjectProfitabilityFinding,
} from "@/features/finance/hooks";
import { DEFAULT_TREND_WINDOW, type TrendWindow } from "@/features/finance/types";
import { ApiError } from "@/lib/api-client";
import {
  CATEGORY_MIX_CSV_FILENAME,
  CATEGORY_MIX_TITLE,
  CategoryMixChart,
  categoryMixCsvRows,
  categoryMixKpi,
} from "./category-mix-chart";
import {
  MarginTrendChart,
  TREND_CSV_FILENAME,
  TREND_TITLE,
  trendCsvRows,
  trendMonthsKpi,
} from "./margin-trend-chart";
import {
  SCOPE_BARS_CSV_FILENAME,
  SCOPE_BARS_TITLE,
  ScopeBudgetBars,
  budgetedScopesKpi,
  scopeBarsCsvRows,
} from "./scope-budget-bars";
import { ProfitabilityFindingCard } from "./profitability-finding-card";
import { TREND_WINDOW_NOTE, TrendWindowFilter } from "./trend-window-filter";

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
 * Three queries, three keys, three failure surfaces: the trend window belongs to
 * the trend alone, so switching it can never restate the lifetime tiles beside it
 * (D-10), and the profitability finding is deliberately excluded from the page
 * loading gate so a slow or failing findings query never delays or blanks the
 * money dashboard.
 */
export default function ProjectFinancialsDashboard({
  projectId,
}: {
  projectId: string;
}) {
  const [trendWindow, setTrendWindow] = useState<TrendWindow>(DEFAULT_TREND_WINDOW);
  const financials = useProjectFinancials(projectId);
  const trend = useProjectMarginTrend(projectId, trendWindow);
  const finding = useProjectProfitabilityFinding(projectId);

  if (financials.isLoading || trend.isLoading) {
    return <FinancialsSkeleton variant="project" />;
  }
  if (isNotFoundError(financials.error)) return <ProjectNotFoundPanel />;
  if (financials.isError || !financials.data) return <LoadErrorPanel />;

  const { name, status, breakdown, scopes } = financials.data;
  const buckets = trend.data?.buckets ?? [];

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

      <ProfitabilityFindingCard
        finding={finding.data ?? null}
        isLoading={finding.isLoading}
        isError={finding.isError}
        incompleteCostData={breakdown.margin?.incomplete ?? false}
      />

      <ChartCard
        title={TREND_TITLE}
        kpiValue={trendMonthsKpi(buckets)}
        icon={TrendingUp}
        csvFilename={TREND_CSV_FILENAME}
        csvRows={trendCsvRows(buckets)}
        ariaLabel={`${TREND_TITLE} chart`}
      >
        <TrendWindowFilter window={trendWindow} onWindowChange={setTrendWindow} />
        <p data-testid="trend-window-note" className="mt-2 text-xs text-gray-500">
          {TREND_WINDOW_NOTE}
        </p>
        <MarginTrendChart buckets={buckets} isRefetching={trend.isFetching} />
      </ChartCard>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        <ChartCard
          title={SCOPE_BARS_TITLE}
          kpiValue={budgetedScopesKpi(scopes)}
          icon={Gauge}
          csvFilename={SCOPE_BARS_CSV_FILENAME}
          csvRows={scopeBarsCsvRows(scopes)}
          ariaLabel={`${SCOPE_BARS_TITLE} chart`}
        >
          <ScopeBudgetBars scopes={scopes} />
        </ChartCard>

        <ChartCard
          title={CATEGORY_MIX_TITLE}
          kpiValue={categoryMixKpi(breakdown.grandTotal)}
          icon={PieChartIcon}
          csvFilename={CATEGORY_MIX_CSV_FILENAME}
          csvRows={categoryMixCsvRows(breakdown.categories, breakdown.labor)}
          ariaLabel={`${CATEGORY_MIX_TITLE} chart`}
        >
          <CategoryMixChart categories={breakdown.categories} labor={breakdown.labor} />
        </ChartCard>
      </div>
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
