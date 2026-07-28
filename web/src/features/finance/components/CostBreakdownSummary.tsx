"use client";

import type { ReactNode } from "react";
import { Info } from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverDescription,
  PopoverTitle,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Separator } from "@/components/ui/separator";
import { formatCurrency } from "@/lib/format";
import { BudgetSummarySection } from "./BudgetSummarySection";
import { FinanceFlagChip } from "./FinanceFlagChip";
import { MarginSummarySection } from "./MarginSummarySection";
import type { CategoryTotal, CostBreakdown, LaborCostSummary } from "../types";

const SECONDS_PER_HOUR = 3600;
const UNBURDENED_TITLE = "Unburdened labor";
const UNBURDENED_BODY =
  "Wage cost only — excludes payroll tax, insurance, overhead.";
const JOB_LEVEL_LABOR_NOTE = "Tracked at job level";
const BREAKDOWN_ERROR = "Couldn't load cost breakdown. Refresh to try again.";
const LABOR_CATEGORY_NAME = "labor";
const CATEGORY_ORDER = ["materials", "subcontractor", "other"] as const;
const LOADING_AMOUNT = "—";

/** "12.5 hrs unrated" / "1 hr unrated" / "2 hrs unrated" — hours always visible (D-05). */
export function formatUnratedHours(unratedSeconds: number): string {
  const hours = unratedSeconds / SECONDS_PER_HOUR;
  const formatted = hours.toFixed(1).replace(/\.0$/, "");
  const unit = formatted === "1" ? "hr" : "hrs";
  return `${formatted} ${unit} unrated`;
}

/** Materials, Subcontractor, Other, then custom names alphabetically. The reserved
 *  labor category is filtered out — labor is rendered from `breakdown.labor`, and the
 *  backend already folded any legacy labor-categorized entries into that figure. */
export function orderedCategories(categories: CategoryTotal[]): CategoryTotal[] {
  const fixedNames: readonly string[] = CATEGORY_ORDER;
  const nonLabor = categories.filter(
    (category) => category.categoryName.toLowerCase() !== LABOR_CATEGORY_NAME
  );
  const fixed = fixedNames.flatMap((name) =>
    nonLabor.filter((category) => category.categoryName.toLowerCase() === name)
  );
  const custom = nonLabor
    .filter((category) => !fixedNames.includes(category.categoryName.toLowerCase()))
    .sort((a, b) => a.categoryName.localeCompare(b.categoryName));
  return [...fixed, ...custom];
}

/** True when there is nothing worth rendering: no categories, zero grand total, no unrated
 *  time, no revenue, and no budget. A margin with revenue keeps the component visible so
 *  the incomplete-data honesty flag can never be hidden (UI-SPEC state 12). A present
 *  budget also keeps it visible — otherwise a freshly-set budget on an empty scope would
 *  be invisible. */
export function isBreakdownEmpty(breakdown: CostBreakdown): boolean {
  const hasUnratedTime = (breakdown.labor?.unratedSeconds ?? 0) > 0;
  const hasRevenue =
    breakdown.margin != null && breakdown.margin.revenueBasis !== "none";
  const hasBudget = breakdown.budget != null;
  return (
    breakdown.categories.length === 0 &&
    Number(breakdown.grandTotal) === 0 &&
    !hasUnratedTime &&
    !hasRevenue &&
    !hasBudget
  );
}

/** "materials" -> "Materials" */
export function displayCategoryName(name: string): string {
  return name.charAt(0).toUpperCase() + name.slice(1);
}

interface CostBreakdownSummaryProps {
  breakdown: CostBreakdown | null | undefined;
  variant: "job" | "trade-scope" | "project";
  isLoading?: boolean;
  isError?: boolean;
}

export function CostBreakdownSummary({
  breakdown,
  variant,
  isLoading = false,
  isError = false,
}: CostBreakdownSummaryProps) {
  if (isError) {
    return <p className="text-sm text-gray-500">{BREAKDOWN_ERROR}</p>;
  }
  if (!isLoading && (!breakdown || isBreakdownEmpty(breakdown))) {
    return null;
  }

  const amountOf = (value: string) =>
    isLoading ? LOADING_AMOUNT : formatCurrency(value);
  const showsBudget = variant !== "job" && !isLoading;

  return (
    <div data-testid="cost-breakdown" className="space-y-2">
      {variant === "trade-scope" ? (
        <TradeScopeLaborRow />
      ) : (
        <LaborRow labor={breakdown?.labor ?? null} amountOf={amountOf} />
      )}
      {orderedCategories(breakdown?.categories ?? []).map((category) => (
        <BreakdownRow
          key={category.categoryId}
          label={displayCategoryName(category.categoryName)}
        >
          <span>{amountOf(category.total)}</span>
        </BreakdownRow>
      ))}
      <Separator />
      <div className="flex items-center justify-between text-sm font-semibold text-gray-900">
        <span>Total</span>
        <span data-testid="breakdown-grand-total">
          {amountOf(breakdown?.grandTotal ?? "0")}
        </span>
      </div>
      {showsBudget && <BudgetSummarySection budget={breakdown?.budget ?? null} />}
      <MarginSummarySection margin={breakdown?.margin ?? null} />
    </div>
  );
}

function BreakdownRow({ label, children }: { label: ReactNode; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="flex items-center gap-1 text-gray-700">{label}</span>
      <span className="flex items-center gap-2">{children}</span>
    </div>
  );
}

function LaborRow({
  labor,
  amountOf,
}: {
  labor: LaborCostSummary | null;
  amountOf: (value: string) => string;
}) {
  const unratedSeconds = labor?.unratedSeconds ?? 0;
  return (
    <BreakdownRow
      label={
        <>
          Labor
          <UnburdenedLaborPopover />
        </>
      }
    >
      {unratedSeconds > 0 && (
        <FinanceFlagChip testId="breakdown-unrated-badge">
          {formatUnratedHours(unratedSeconds)}
        </FinanceFlagChip>
      )}
      <span data-testid="breakdown-labor-amount" className="font-semibold">
        {amountOf(labor?.total ?? "0")}
      </span>
    </BreakdownRow>
  );
}

function TradeScopeLaborRow() {
  return (
    <BreakdownRow label="Labor">
      <span className="text-xs text-gray-500">{JOB_LEVEL_LABOR_NOTE}</span>
    </BreakdownRow>
  );
}

function UnburdenedLaborPopover() {
  return (
    <Popover>
      <PopoverTrigger
        aria-label="About labor cost"
        className="text-gray-400 hover:text-gray-600"
      >
        <Info className="h-3.5 w-3.5" />
      </PopoverTrigger>
      <PopoverContent>
        <PopoverTitle>{UNBURDENED_TITLE}</PopoverTitle>
        <PopoverDescription>{UNBURDENED_BODY}</PopoverDescription>
      </PopoverContent>
    </Popover>
  );
}
