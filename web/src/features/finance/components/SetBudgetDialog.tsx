"use client";

import { useState } from "react";
import { toast } from "sonner";
import { ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { formatCurrency } from "@/lib/format";
import { useDeleteBudget, useSetBudget, useUpdateBudget } from "../hooks";
import { formatPercentUsed } from "./BudgetSummarySection";
import type { BudgetVsActual } from "../types";

const CREATE_TITLE_PREFIX = "Set budget — ";
const EDIT_TITLE_PREFIX = "Edit budget — ";
const AMOUNT_FIELD_LABEL = "Budget amount";
const CREATE_HELPER_TEXT = "You'll get alerts at 80% and 100% of this amount.";
const EDIT_HELPER_TEXT = "Increasing the budget re-arms the 80% and 100% alerts.";
const BELOW_SPEND_NOTE = "Below current spend — the overrun alert will fire.";
const CURRENT_BUDGET_EYEBROW = "CURRENT BUDGET";
const AMOUNT_VALIDATION_MESSAGE = "Enter a budget greater than $0.";
const CEILING_VALIDATION_MESSAGE = "Enter an amount under $100,000,000.";
const SAVE_ERROR_MESSAGE = "Could not save budget. Please try again.";
const REMOVE_ERROR_MESSAGE = "Could not remove budget. Please try again.";
const DUPLICATE_BUDGET_MESSAGE = "A budget already exists here. Refresh to see it.";
const REMOVED_TOAST_MESSAGE = "Budget removed.";
const CREATE_SUBMIT_LABEL = "Set Budget";
const EDIT_SUBMIT_LABEL = "Save Budget";
const REMOVE_BUTTON_LABEL = "Remove budget";
const REMOVE_CONFIRM_LABEL = "Remove Budget";
const CANCEL_LABEL = "Cancel";

/** NUMERIC(10,2) ceiling on the backend budgets table. */
const MAX_BUDGET_AMOUNT = 99_999_999.99;
const HTTP_CONFLICT = 409;
/** Digits with at most two decimal places — matches the validation contract. */
const AMOUNT_PATTERN = /^\d+(\.\d{1,2})?$/;

type AnchorNoun = "project" | "scope";

function createSuccessToast(total: string): string {
  return `Budget set — ${formatCurrency(total)}.`;
}

function editSuccessToast(total: string): string {
  return `Budget updated — ${formatCurrency(total)}.`;
}

function removeConfirmationCopy(anchorNoun: AnchorNoun): string {
  return `Remove this budget? Budget tracking and alerts stop for this ${anchorNoun}. Cost entries are not affected.`;
}

function validateBudgetAmount(amount: string): string | null {
  const trimmed = amount.trim();
  if (!AMOUNT_PATTERN.test(trimmed) || Number(trimmed) <= 0) {
    return AMOUNT_VALIDATION_MESSAGE;
  }
  if (Number(trimmed) > MAX_BUDGET_AMOUNT) return CEILING_VALIDATION_MESSAGE;
  return null;
}

function isDuplicateBudgetError(error: unknown): boolean {
  return error instanceof ApiError && error.status === HTTP_CONFLICT;
}

function isBelowCurrentSpend(amount: string, budget: BudgetVsActual): boolean {
  const entered = Number(amount.trim());
  return (
    Number.isFinite(entered) && entered > 0 && entered < Number(budget.spent)
  );
}

interface SetBudgetDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Anchor + display name; exactly one id is set. */
  anchor: { projectId?: string; tradeScopeId?: string; name: string };
  /** Present = edit mode; null = create mode. */
  budget: BudgetVsActual | null;
}

export function SetBudgetDialog({
  open,
  onOpenChange,
  anchor,
  budget,
}: SetBudgetDialogProps) {
  /** null = untouched — the field shows the current budget total (or empty). */
  const [editedAmount, setEditedAmount] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [confirmingRemove, setConfirmingRemove] = useState(false);

  const setBudget = useSetBudget();
  const updateBudget = useUpdateBudget();
  const deleteBudget = useDeleteBudget();

  const isEditMode = budget != null;
  const amount = editedAmount ?? budget?.total ?? "";
  const isSaving = setBudget.isPending || updateBudget.isPending;

  const handleOpenChange = (nextOpen: boolean) => {
    if (!nextOpen) {
      setEditedAmount(null);
      setFormError(null);
      setConfirmingRemove(false);
    }
    onOpenChange(nextOpen);
  };

  const closeDialog = () => handleOpenChange(false);

  const handleSaveError = (error: unknown) => {
    toast.error(
      isDuplicateBudgetError(error) ? DUPLICATE_BUDGET_MESSAGE : SAVE_ERROR_MESSAGE
    );
  };

  const saveBudget = (total: string) => {
    if (budget) {
      updateBudget.mutate(
        { budgetId: budget.budgetId, total },
        {
          onSuccess: () => {
            toast.success(editSuccessToast(total));
            closeDialog();
          },
          onError: handleSaveError,
        }
      );
      return;
    }
    setBudget.mutate(
      { projectId: anchor.projectId, tradeScopeId: anchor.tradeScopeId, total },
      {
        onSuccess: () => {
          toast.success(createSuccessToast(total));
          closeDialog();
        },
        onError: handleSaveError,
      }
    );
  };

  const handleSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    const validationError = validateBudgetAmount(amount);
    if (validationError) {
      setFormError(validationError);
      return;
    }
    setFormError(null);
    saveBudget(amount.trim());
  };

  const handleRemove = () => {
    if (!budget) return;
    deleteBudget.mutate(budget.budgetId, {
      onSuccess: () => {
        toast.success(REMOVED_TOAST_MESSAGE);
        closeDialog();
      },
      onError: () => toast.error(REMOVE_ERROR_MESSAGE),
    });
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-md" data-testid="set-budget-dialog">
        <DialogHeader>
          <DialogTitle className="text-xl font-semibold text-gray-900">
            {(isEditMode ? EDIT_TITLE_PREFIX : CREATE_TITLE_PREFIX) + anchor.name}
          </DialogTitle>
        </DialogHeader>

        {confirmingRemove && budget ? (
          <RemoveBudgetConfirmation
            anchorNoun={anchor.projectId ? "project" : "scope"}
            isRemoving={deleteBudget.isPending}
            onConfirm={handleRemove}
            onCancel={() => setConfirmingRemove(false)}
          />
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            {budget && <CurrentBudgetHeadline budget={budget} />}
            <BudgetAmountField
              amount={amount}
              onAmountChange={setEditedAmount}
              helperText={isEditMode ? EDIT_HELPER_TEXT : CREATE_HELPER_TEXT}
              showsBelowSpendNote={
                budget != null && isBelowCurrentSpend(amount, budget)
              }
            />
            {formError && (
              <p className="text-sm text-destructive" role="alert">
                {formError}
              </p>
            )}
            <DialogFooter className={isEditMode ? "sm:justify-between" : undefined}>
              {isEditMode && (
                <Button
                  type="button"
                  variant="ghost"
                  className="text-destructive hover:text-destructive"
                  data-testid="budget-remove-button"
                  onClick={() => setConfirmingRemove(true)}
                >
                  {REMOVE_BUTTON_LABEL}
                </Button>
              )}
              <Button type="submit" disabled={isSaving}>
                {isEditMode ? EDIT_SUBMIT_LABEL : CREATE_SUBMIT_LABEL}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}

function CurrentBudgetHeadline({ budget }: { budget: BudgetVsActual }) {
  const spendCaption = `Current spend: ${formatCurrency(budget.spent)} (${formatPercentUsed(budget.percentUsed)}%).`;
  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-wide text-gray-500">
        {CURRENT_BUDGET_EYEBROW}
      </p>
      <p
        className="text-2xl font-semibold text-gray-900"
        data-testid="current-budget-figure"
      >
        {formatCurrency(budget.total)}
      </p>
      <p className="text-xs text-gray-500">{spendCaption}</p>
    </div>
  );
}

function BudgetAmountField({
  amount,
  onAmountChange,
  helperText,
  showsBelowSpendNote,
}: {
  amount: string;
  onAmountChange: (value: string) => void;
  helperText: string;
  showsBelowSpendNote: boolean;
}) {
  return (
    <div className="grid gap-2">
      <Label htmlFor="budget-amount">{AMOUNT_FIELD_LABEL}</Label>
      <div className="relative">
        <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-gray-500">
          $
        </span>
        <Input
          id="budget-amount"
          type="text"
          inputMode="decimal"
          autoFocus
          className="pl-7"
          data-testid="budget-amount-input"
          value={amount}
          onChange={(event) => onAmountChange(event.target.value)}
        />
      </div>
      <p className="text-xs text-gray-500">{helperText}</p>
      {showsBelowSpendNote && (
        <p className="text-xs text-gray-500">{BELOW_SPEND_NOTE}</p>
      )}
    </div>
  );
}

function RemoveBudgetConfirmation({
  anchorNoun,
  isRemoving,
  onConfirm,
  onCancel,
}: {
  anchorNoun: AnchorNoun;
  isRemoving: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="space-y-4">
      <p className="text-sm text-gray-700">{removeConfirmationCopy(anchorNoun)}</p>
      <DialogFooter>
        <Button type="button" variant="outline" autoFocus onClick={onCancel}>
          {CANCEL_LABEL}
        </Button>
        <Button
          type="button"
          variant="destructive"
          data-testid="budget-remove-confirm"
          disabled={isRemoving}
          onClick={onConfirm}
        >
          {REMOVE_CONFIRM_LABEL}
        </Button>
      </DialogFooter>
    </div>
  );
}
