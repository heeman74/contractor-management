"use client";

import { useRouter } from "next/navigation";

import { ChartEmptyState } from "@/components/shared/chart-empty-state";
import { PERCENT_AXIS_CLAMP } from "@/components/shared/chart-theme";
import { clampPercentForAxis } from "@/features/finance/financials-format";
import {
  INACTIVE_PROJECT_STATUSES,
  type BudgetVsActual,
  type ProjectFinancialsRow,
} from "@/features/finance/types";
import { formatCurrency, formatStatus } from "@/lib/format";
import { BulletBarChart, type BulletBarRow } from "./bullet-bar-chart";

export const BUDGET_BARS_TEST_ID = "project-budget-bars";
export const BUDGET_BARS_TITLE = "Budget vs Actual by Project";
export const BUDGET_BARS_CSV_FILENAME = "budget-vs-actual-by-project.csv";

const EMPTY_HEADING = "No budgets set";
const EMPTY_BODY = "Set a budget on a project or trade scope to track spend against it.";
const CSV_HEADER = ["Project", "Status", "Budget", "Spent", "Percent used"];
const SINGLE_PROJECT = 1;
const NO_PROJECTS = 0;

type BudgetedProject = ProjectFinancialsRow & { budget: BudgetVsActual };

function isBudgeted(row: ProjectFinancialsRow): row is BudgetedProject {
  return row.budget !== null;
}

/** The one place a money string becomes a number: everything rendered still
 *  formats from the original backend string. */
export function toBudgetBarRows(projects: ProjectFinancialsRow[]): BulletBarRow[] {
  const truePercentOf = (row: BudgetedProject) => parseFloat(row.budget.percentUsed);
  return projects
    .filter(isBudgeted)
    .sort((left, right) => truePercentOf(right) - truePercentOf(left))
    .map((row) => toBulletBarRow(row, truePercentOf(row)));
}

function toBulletBarRow(row: BudgetedProject, truePercent: number): BulletBarRow {
  return {
    id: row.projectId,
    label: row.name,
    percentUsed: row.budget.percentUsed,
    remaining: row.budget.remaining,
    percentUsedClamped: clampPercentForAxis(row.budget.percentUsed),
    spentLabel: formatCurrency(row.budget.spent),
    budgetLabel: formatCurrency(row.budget.total),
    statusLabel: formatStatus(row.status),
    isInactive: INACTIVE_PROJECT_STATUSES.includes(row.status),
    isOverClamp: truePercent > PERCENT_AXIS_CLAMP,
  };
}

/** Full names and true percents: an export never inherits the chart's clamping. */
export function budgetBarsCsvRows(projects: ProjectFinancialsRow[]): string[][] {
  return [
    CSV_HEADER,
    ...projects
      .filter(isBudgeted)
      .map((row) => [
        row.name,
        row.status,
        row.budget.total,
        row.budget.spent,
        row.budget.percentUsed,
      ]),
  ];
}

/** "{N} of {M} projects budgeted" — the chart is not the whole portfolio, and says so. */
export function budgetedProjectsKpi(projects: ProjectFinancialsRow[]): string {
  return `${projects.filter(isBudgeted).length} of ${projects.length} projects budgeted`;
}

function unbudgetedNote(count: number): string {
  const subject = count === SINGLE_PROJECT ? "1 project has" : `${count} projects have`;
  return `${subject} no budget set.`;
}

/** The company-overview wrapper: it knows about projects so the bullet chart
 *  does not have to. */
export function ProjectBudgetBars({ projects }: { projects: ProjectFinancialsRow[] }) {
  const router = useRouter();
  const rows = toBudgetBarRows(projects);
  const unbudgetedCount = projects.length - rows.length;

  if (rows.length === NO_PROJECTS) {
    return <ChartEmptyState heading={EMPTY_HEADING} body={EMPTY_BODY} />;
  }

  return (
    <div>
      <BulletBarChart
        rows={rows}
        testId={BUDGET_BARS_TEST_ID}
        onRowClick={(projectId) => router.push(`/financials/${projectId}`)}
      />
      {unbudgetedCount > NO_PROJECTS && (
        <p
          data-testid={`${BUDGET_BARS_TEST_ID}-unbudgeted-note`}
          className="mt-2 text-xs text-gray-500"
        >
          {unbudgetedNote(unbudgetedCount)}
        </p>
      )}
    </div>
  );
}
