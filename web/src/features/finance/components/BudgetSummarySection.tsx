"use client";

import type { ReactNode } from "react";
import { Separator } from "@/components/ui/separator";
import { formatCurrency, formatSignedCurrency } from "@/lib/format";
import { FinanceFlagChip } from "./FinanceFlagChip";
import type { BudgetVsActual } from "../types";

const BUDGET_LABEL = "Budget";
const SPENT_LABEL = "Spent";
const REMAINING_LABEL = "Remaining";
const NEARING_BUDGET_CHIP_LABEL = "Nearing budget";
const FIGURE_SEPARATOR = " · ";
const WARNING_PERCENT = 80;
const REMAINING_FIGURE_CLASS = "text-sm font-semibold";
const OVERRUN_FIGURE_CLASS = "text-sm font-semibold text-destructive";

/** "82.0" -> "82", "82.5" -> "82.5" — only a trailing ".0" is dropped. */
export function formatPercentUsed(percentUsed: string): string {
  return percentUsed.replace(/\.0$/, "");
}

interface BudgetSummarySectionProps {
  budget: BudgetVsActual | null | undefined;
}

/** Budget/Spent/Remaining triad between the breakdown Total row and the margin
 *  section (34-UI-SPEC states 1, 3-10). Band classification derives only from
 *  the backend strings — the client never divides. */
export function BudgetSummarySection({ budget }: BudgetSummarySectionProps) {
  if (!budget) return null;
  const isOverBudget = Number(budget.remaining) < 0;
  const isNearingBudget =
    Number(budget.remaining) > 0 &&
    Number(budget.percentUsed) >= WARNING_PERCENT;
  const spentFigure = `${formatCurrency(budget.spent)}${FIGURE_SEPARATOR}${formatPercentUsed(budget.percentUsed)}%`;
  return (
    <div data-testid="budget-section" className="space-y-2">
      <Separator />
      <BudgetRow label={BUDGET_LABEL}>
        <span data-testid="budget-amount">{formatCurrency(budget.total)}</span>
      </BudgetRow>
      <BudgetRow label={SPENT_LABEL}>
        <span data-testid="budget-spent">{spentFigure}</span>
      </BudgetRow>
      <BudgetRow label={REMAINING_LABEL}>
        {isNearingBudget && (
          <FinanceFlagChip testId="budget-warning-chip">
            {NEARING_BUDGET_CHIP_LABEL}
          </FinanceFlagChip>
        )}
        <span
          data-testid="budget-remaining"
          className={isOverBudget ? OVERRUN_FIGURE_CLASS : REMAINING_FIGURE_CLASS}
        >
          {isOverBudget
            ? formatSignedCurrency(budget.remaining)
            : formatCurrency(budget.remaining)}
        </span>
      </BudgetRow>
    </div>
  );
}

function BudgetRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-gray-700">{label}</span>
      <span className="flex items-center gap-2">{children}</span>
    </div>
  );
}
