"use client";

import { Gauge } from "lucide-react";

import { ChartCard } from "@/app/(dashboard)/reports/_components/chart-card";
import { useCompanyFinancials } from "@/features/finance/hooks";
import { FinanceSummaryTiles } from "./finance-summary-tiles";
import { FinancialsSkeleton } from "./financials-skeleton";
import {
  BUDGET_BARS_CSV_FILENAME,
  BUDGET_BARS_TITLE,
  ProjectBudgetBars,
  budgetBarsCsvRows,
  budgetedProjectsKpi,
} from "./project-budget-bars";

const LOAD_ERROR_MESSAGE = "Couldn't load financials. Refresh to try again.";
const ERROR_PANEL_CLASS =
  "rounded-xl border border-red-200 bg-red-50 px-6 py-12 text-center text-sm font-medium text-red-800";

const REVENUE_TILE_TITLE = "Portfolio revenue";
const COST_TILE_TITLE = "Portfolio cost";
const MARGIN_TILE_TITLE = "Portfolio margin";
const PORTFOLIO_TEST_ID_PREFIX = "portfolio";

/**
 * The only hook-owning component on `/financials`. Everything below it is
 * presentational and takes already-parsed props, which is what keeps the
 * null-handling tests free of a query client.
 *
 * The failure surface is an inline panel, not the Reports page's permanent
 * notification: on a finance surface the honest thing is to replace the figures,
 * never to leave stale money on screen behind a floating message.
 */
export default function CompanyFinancialsDashboard() {
  const { data, isLoading, isError } = useCompanyFinancials();

  if (isLoading) return <FinancialsSkeleton variant="company" />;
  if (isError || !data) {
    return (
      <div data-testid="financials-error" className={ERROR_PANEL_CLASS}>
        {LOAD_ERROR_MESSAGE}
      </div>
    );
  }

  const { portfolio, projects } = data;

  return (
    <div className="space-y-6">
      <FinanceSummaryTiles
        revenueTitle={REVENUE_TILE_TITLE}
        costTitle={COST_TILE_TITLE}
        marginTitle={MARGIN_TILE_TITLE}
        cost={portfolio.cost}
        margin={portfolio.margin}
        testIdPrefix={PORTFOLIO_TEST_ID_PREFIX}
        quotedRevenue={portfolio.quotedRevenue}
        incompleteProjectCount={portfolio.incompleteProjectCount}
      />

      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        <ChartCard
          title={BUDGET_BARS_TITLE}
          kpiValue={budgetedProjectsKpi(projects)}
          icon={Gauge}
          csvFilename={BUDGET_BARS_CSV_FILENAME}
          csvRows={budgetBarsCsvRows(projects)}
          ariaLabel={`${BUDGET_BARS_TITLE} chart`}
        >
          <ProjectBudgetBars projects={projects} />
        </ChartCard>
      </div>
    </div>
  );
}
