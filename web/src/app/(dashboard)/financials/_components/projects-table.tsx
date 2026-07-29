"use client";

import Link from "next/link";

import { ChartEmptyState } from "@/components/shared/chart-empty-state";
import { StatusBadge } from "@/components/shared/status-badge";
import { Card, CardContent } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  formatMarginDollars,
  formatMarginPercent,
} from "@/features/finance/components/MarginSummarySection";
import {
  INACTIVE_PROJECT_STATUSES,
  type ProjectFinancialsRow,
} from "@/features/finance/types";
import { formatCurrency } from "@/lib/format";

export const PROJECTS_TABLE_TEST_ID = "projects-table";
export const PROJECTS_TABLE_TITLE = "All Projects";

const COLUMN_HEADERS = ["Project", "Status", "Revenue", "Cost", "Margin", "Budget used"];
const INACTIVE_SEPARATOR_LABEL =
  "Inactive projects — still included in portfolio totals";
const NO_BUDGET_LABEL = "No budget";
const DRILL_DOWN_LABEL = "View financials";
const ABSENT_CELL = "—";
const EMPTY_HEADING = "No projects yet";
const EMPTY_BODY = "Create a project to start tracking margin and budget.";
const NEGATIVE_PREFIX = "-";
/** 14px cells, so the red-800 family — the destructive token is sub-AA at this size. */
const NEGATIVE_CELL_CLASS = "text-red-800";
const INACTIVE_ROW_CLASS = "text-muted-foreground";
const SEPARATOR_COLUMN_SPAN = COLUMN_HEADERS.length + 1;
const NO_PROJECTS = 0;

interface ProjectGroups {
  active: ProjectFinancialsRow[];
  inactive: ProjectFinancialsRow[];
}

/** Largest exposure first within each group; a name breaks a tie so the order is
 *  stable between renders. on_hold counts as active: a paused project is still an
 *  open financial commitment. */
export function groupProjectsByActivity(
  projects: ProjectFinancialsRow[]
): ProjectGroups {
  const byCostDescending = (left: ProjectFinancialsRow, right: ProjectFinancialsRow) =>
    Number(right.cost) - Number(left.cost) || left.name.localeCompare(right.name);
  const isInactive = (row: ProjectFinancialsRow) =>
    INACTIVE_PROJECT_STATUSES.includes(row.status);

  return {
    active: projects.filter((row) => !isInactive(row)).sort(byCostDescending),
    inactive: projects.filter(isInactive).sort(byCostDescending),
  };
}

function moneyCell(value: string | null): string {
  return value == null ? ABSENT_CELL : formatCurrency(value);
}

function marginCell(value: string | null): string {
  return value == null ? ABSENT_CELL : formatMarginDollars(value);
}

function budgetUsedCell(project: ProjectFinancialsRow): string {
  if (project.budget == null) return NO_BUDGET_LABEL;
  return `${formatMarginPercent(project.budget.percentUsed)}%`;
}

/**
 * The complete, deep-linkable inventory. The bullet chart above it covers only
 * budgeted projects; nothing is ever dropped from this table, and the inactive
 * group sits below a separator that says so out loud.
 */
export function ProjectsTable({ projects }: { projects: ProjectFinancialsRow[] }) {
  const { active, inactive } = groupProjectsByActivity(projects);

  return (
    <Card>
      <CardContent className="pt-4">
        <p className="text-sm text-gray-500">{PROJECTS_TABLE_TITLE}</p>
        {projects.length === NO_PROJECTS ? (
          <ChartEmptyState heading={EMPTY_HEADING} body={EMPTY_BODY} />
        ) : (
          <Table data-testid={PROJECTS_TABLE_TEST_ID} className="mt-4">
            <TableHeader>
              <TableRow>
                {COLUMN_HEADERS.map((header) => (
                  <TableHead key={header}>{header}</TableHead>
                ))}
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {active.map((project) => (
                <ProjectRow key={project.projectId} project={project} />
              ))}
              {inactive.length > NO_PROJECTS && <InactiveSeparatorRow />}
              {inactive.map((project) => (
                <ProjectRow key={project.projectId} project={project} isInactive />
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

function InactiveSeparatorRow() {
  return (
    <TableRow data-testid={`${PROJECTS_TABLE_TEST_ID}-inactive-header`}>
      <TableCell
        colSpan={SEPARATOR_COLUMN_SPAN}
        className="text-xs uppercase tracking-wide text-gray-500"
      >
        {INACTIVE_SEPARATOR_LABEL}
      </TableCell>
    </TableRow>
  );
}

function ProjectRow({
  project,
  isInactive = false,
}: {
  project: ProjectFinancialsRow;
  isInactive?: boolean;
}) {
  const margin = marginCell(project.margin.margin);
  const isNegativeMargin = margin.startsWith(NEGATIVE_PREFIX);

  return (
    <TableRow className={isInactive ? INACTIVE_ROW_CLASS : undefined}>
      <TableCell>{project.name}</TableCell>
      <TableCell>
        <StatusBadge status={project.status} size="sm" />
      </TableCell>
      <TableCell data-testid={`${PROJECTS_TABLE_TEST_ID}-revenue-${project.projectId}`}>
        {moneyCell(project.margin.revenue)}
      </TableCell>
      <TableCell>{formatCurrency(project.cost)}</TableCell>
      <TableCell
        data-testid={`${PROJECTS_TABLE_TEST_ID}-margin-${project.projectId}`}
        className={isNegativeMargin ? NEGATIVE_CELL_CLASS : undefined}
      >
        {margin}
      </TableCell>
      <TableCell
        data-testid={`${PROJECTS_TABLE_TEST_ID}-budget-used-${project.projectId}`}
      >
        {budgetUsedCell(project)}
      </TableCell>
      <TableCell>
        <Link
          href={`/financials/${project.projectId}`}
          aria-label={`${DRILL_DOWN_LABEL} for ${project.name}`}
          className="text-sm text-brand hover:underline"
        >
          {DRILL_DOWN_LABEL}
        </Link>
      </TableCell>
    </TableRow>
  );
}
