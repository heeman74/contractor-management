import React from "react";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { toast } from "sonner";
import { SetBudgetDialog } from "../components/SetBudgetDialog";
import { useSetBudget, useUpdateBudget, useDeleteBudget } from "../hooks";
import { ApiError } from "@/lib/api-client";
import type { BudgetVsActual } from "../types";

jest.mock("sonner", () => ({ toast: { success: jest.fn(), error: jest.fn() } }));
jest.mock("../hooks", () => ({
  useSetBudget: jest.fn(),
  useUpdateBudget: jest.fn(),
  useDeleteBudget: jest.fn(),
}));
jest.mock("@/lib/api-client", () => ({
  ApiError: class ApiError extends Error {
    status: number;
    detail: string;
    constructor(status: number, detail: string) {
      super(detail);
      this.status = status;
      this.detail = detail;
    }
  },
}));

const mockUseSetBudget = useSetBudget as jest.Mock;
const mockUseUpdateBudget = useUpdateBudget as jest.Mock;
const mockUseDeleteBudget = useDeleteBudget as jest.Mock;
const mockToastSuccess = toast.success as jest.Mock;
const mockToastError = toast.error as jest.Mock;

type MutationOutcome = { success: true } | { success: false; error: unknown };

function mutationMock(outcome: MutationOutcome = { success: true }) {
  return {
    mutate: jest.fn((_variables: unknown, options?: {
      onSuccess?: () => void;
      onError?: (error: unknown) => void;
    }) => {
      if (outcome.success) options?.onSuccess?.();
      else options?.onError?.(outcome.error);
    }),
    isPending: false,
  };
}

const PROJECT_ANCHOR = { projectId: "p-1", name: "Riverside Remodel" };
const SCOPE_ANCHOR = { tradeScopeId: "ts-1", name: "Plumbing scope" };

const SCOPE_BUDGET: BudgetVsActual = {
  budgetId: "b-1",
  total: "10000.00",
  spent: "8200.00",
  remaining: "1800.00",
  percentUsed: "82.0",
};

function renderDialog(
  props: Partial<React.ComponentProps<typeof SetBudgetDialog>> = {}
) {
  const onOpenChange = jest.fn();
  const utils = render(
    <SetBudgetDialog
      open
      onOpenChange={onOpenChange}
      anchor={PROJECT_ANCHOR}
      budget={null}
      {...props}
    />
  );
  return { onOpenChange, ...utils };
}

function amountInput() {
  return screen.getByTestId("budget-amount-input");
}

describe("SetBudgetDialog", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockUseSetBudget.mockReturnValue(mutationMock());
    mockUseUpdateBudget.mockReturnValue(mutationMock());
    mockUseDeleteBudget.mockReturnValue(mutationMock());
  });

  test("create mode renders the title, create helper, and Set Budget submit", () => {
    renderDialog();

    expect(screen.getByText("Set budget — Riverside Remodel")).toBeInTheDocument();
    expect(
      screen.getByText("You'll get alerts at 80% and 100% of this amount.")
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Set Budget" })).toBeInTheDocument();
    expect(screen.queryByText("CURRENT BUDGET")).not.toBeInTheDocument();
    expect(screen.queryByTestId("budget-remove-button")).not.toBeInTheDocument();
  });

  test("edit mode renders the headline, spend caption, edit helper, and Save Budget", () => {
    renderDialog({ anchor: SCOPE_ANCHOR, budget: SCOPE_BUDGET });

    expect(screen.getByText("Edit budget — Plumbing scope")).toBeInTheDocument();
    expect(screen.getByText("CURRENT BUDGET")).toBeInTheDocument();
    expect(screen.getByText("$10000.00")).toBeInTheDocument();
    expect(screen.getByText("Current spend: $8200.00 (82%).")).toBeInTheDocument();
    expect(
      screen.getByText("Increasing the budget re-arms the 80% and 100% alerts.")
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Save Budget" })).toBeInTheDocument();
    expect(amountInput()).toHaveValue("10000.00");
  });

  test("an amount below current spend shows the live note and keeps submit enabled", async () => {
    const user = userEvent.setup();
    renderDialog({ anchor: SCOPE_ANCHOR, budget: SCOPE_BUDGET });

    await user.clear(amountInput());
    await user.type(amountInput(), "5000");

    expect(
      screen.getByText("Below current spend — the overrun alert will fire.")
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Save Budget" })).toBeEnabled();
  });

  test("the below-spend note stays hidden while the amount covers current spend", async () => {
    const user = userEvent.setup();
    renderDialog({ anchor: SCOPE_ANCHOR, budget: SCOPE_BUDGET });

    await user.clear(amountInput());
    await user.type(amountInput(), "12000");

    expect(
      screen.queryByText("Below current spend — the overrun alert will fire.")
    ).not.toBeInTheDocument();
  });

  test.each(["", "0"])(
    "submitting %p shows the greater-than-zero message and calls no mutation",
    async (value) => {
      const user = userEvent.setup();
      const setBudget = mutationMock();
      mockUseSetBudget.mockReturnValue(setBudget);
      renderDialog();

      if (value) await user.type(amountInput(), value);
      await user.click(screen.getByRole("button", { name: "Set Budget" }));

      expect(
        await screen.findByText("Enter a budget greater than $0.")
      ).toBeInTheDocument();
      expect(setBudget.mutate).not.toHaveBeenCalled();
    }
  );

  test("more than two decimal places is rejected as an invalid amount", async () => {
    const user = userEvent.setup();
    const setBudget = mutationMock();
    mockUseSetBudget.mockReturnValue(setBudget);
    renderDialog();

    await user.type(amountInput(), "100.999");
    await user.click(screen.getByRole("button", { name: "Set Budget" }));

    expect(
      await screen.findByText("Enter a budget greater than $0.")
    ).toBeInTheDocument();
    expect(setBudget.mutate).not.toHaveBeenCalled();
  });

  test("an amount over 99,999,999.99 shows the ceiling message and calls no mutation", async () => {
    const user = userEvent.setup();
    const setBudget = mutationMock();
    mockUseSetBudget.mockReturnValue(setBudget);
    renderDialog();

    await user.type(amountInput(), "100000000");
    await user.click(screen.getByRole("button", { name: "Set Budget" }));

    expect(
      await screen.findByText("Enter an amount under $100,000,000.")
    ).toBeInTheDocument();
    expect(setBudget.mutate).not.toHaveBeenCalled();
  });

  test("a successful create sends the project anchor, toasts the amount, and closes", async () => {
    const user = userEvent.setup();
    const setBudget = mutationMock();
    mockUseSetBudget.mockReturnValue(setBudget);
    const { onOpenChange } = renderDialog();

    await user.type(amountInput(), "10000");
    await user.click(screen.getByRole("button", { name: "Set Budget" }));

    expect(setBudget.mutate).toHaveBeenCalledTimes(1);
    expect(setBudget.mutate.mock.calls[0][0]).toEqual({
      projectId: "p-1",
      tradeScopeId: undefined,
      total: "10000",
    });
    expect(mockToastSuccess).toHaveBeenCalledWith("Budget set — $10000.00.");
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  test("a create on the scope surface sends the trade-scope anchor", async () => {
    const user = userEvent.setup();
    const setBudget = mutationMock();
    mockUseSetBudget.mockReturnValue(setBudget);
    renderDialog({ anchor: SCOPE_ANCHOR });

    await user.type(amountInput(), "500");
    await user.click(screen.getByRole("button", { name: "Set Budget" }));

    expect(setBudget.mutate.mock.calls[0][0]).toEqual({
      projectId: undefined,
      tradeScopeId: "ts-1",
      total: "500",
    });
  });

  test("a successful edit calls the update mutation and toasts the new amount", async () => {
    const user = userEvent.setup();
    const updateBudget = mutationMock();
    mockUseUpdateBudget.mockReturnValue(updateBudget);
    const { onOpenChange } = renderDialog({
      anchor: SCOPE_ANCHOR,
      budget: SCOPE_BUDGET,
    });

    await user.clear(amountInput());
    await user.type(amountInput(), "12000");
    await user.click(screen.getByRole("button", { name: "Save Budget" }));

    expect(updateBudget.mutate).toHaveBeenCalledTimes(1);
    expect(updateBudget.mutate.mock.calls[0][0]).toEqual({
      budgetId: "b-1",
      total: "12000",
    });
    expect(mockToastSuccess).toHaveBeenCalledWith("Budget updated — $12000.00.");
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  test("a failed save toasts the error and keeps the dialog open", async () => {
    const user = userEvent.setup();
    mockUseSetBudget.mockReturnValue(
      mutationMock({ success: false, error: new Error("network down") })
    );
    const { onOpenChange } = renderDialog();

    await user.type(amountInput(), "10000");
    await user.click(screen.getByRole("button", { name: "Set Budget" }));

    expect(mockToastError).toHaveBeenCalledWith(
      "Could not save budget. Please try again."
    );
    expect(onOpenChange).not.toHaveBeenCalled();
    expect(screen.getByTestId("set-budget-dialog")).toBeInTheDocument();
  });

  test("a 409 response toasts the duplicate-budget message", async () => {
    const user = userEvent.setup();
    mockUseSetBudget.mockReturnValue(
      mutationMock({ success: false, error: new ApiError(409, "duplicate") })
    );
    renderDialog();

    await user.type(amountInput(), "10000");
    await user.click(screen.getByRole("button", { name: "Set Budget" }));

    expect(mockToastError).toHaveBeenCalledWith(
      "A budget already exists here. Refresh to see it."
    );
  });

  test("Remove budget swaps to the confirmation, and Remove Budget deletes with a toast", async () => {
    const user = userEvent.setup();
    const deleteBudget = mutationMock();
    mockUseDeleteBudget.mockReturnValue(deleteBudget);
    const { onOpenChange } = renderDialog({
      anchor: SCOPE_ANCHOR,
      budget: SCOPE_BUDGET,
    });

    await user.click(screen.getByTestId("budget-remove-button"));

    expect(
      screen.getByText(
        "Remove this budget? Budget tracking and alerts stop for this scope. Cost entries are not affected."
      )
    ).toBeInTheDocument();
    expect(screen.queryByTestId("budget-amount-input")).not.toBeInTheDocument();

    await user.click(screen.getByTestId("budget-remove-confirm"));

    expect(deleteBudget.mutate).toHaveBeenCalledTimes(1);
    expect(deleteBudget.mutate.mock.calls[0][0]).toBe("b-1");
    expect(mockToastSuccess).toHaveBeenCalledWith("Budget removed.");
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  test("the project-anchored confirmation names the project", async () => {
    const user = userEvent.setup();
    renderDialog({
      anchor: PROJECT_ANCHOR,
      budget: { ...SCOPE_BUDGET, budgetId: "b-2" },
    });

    await user.click(screen.getByTestId("budget-remove-button"));

    expect(
      screen.getByText(
        "Remove this budget? Budget tracking and alerts stop for this project. Cost entries are not affected."
      )
    ).toBeInTheDocument();
  });

  test("a failed remove toasts the remove error and keeps the dialog open", async () => {
    const user = userEvent.setup();
    mockUseDeleteBudget.mockReturnValue(
      mutationMock({ success: false, error: new Error("boom") })
    );
    const { onOpenChange } = renderDialog({
      anchor: SCOPE_ANCHOR,
      budget: SCOPE_BUDGET,
    });

    await user.click(screen.getByTestId("budget-remove-button"));
    await user.click(screen.getByTestId("budget-remove-confirm"));

    expect(mockToastError).toHaveBeenCalledWith(
      "Could not remove budget. Please try again."
    );
    expect(onOpenChange).not.toHaveBeenCalled();
  });

  test("Cancel returns from the confirmation to the edit form", async () => {
    const user = userEvent.setup();
    renderDialog({ anchor: SCOPE_ANCHOR, budget: SCOPE_BUDGET });

    await user.click(screen.getByTestId("budget-remove-button"));
    await user.click(screen.getByRole("button", { name: "Cancel" }));

    expect(amountInput()).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Save Budget" })).toBeInTheDocument();
  });

  test("reopening after a cancelled edit shows the original amount again", async () => {
    const user = userEvent.setup();
    const onOpenChange = jest.fn();
    const { rerender } = render(
      <SetBudgetDialog
        open
        onOpenChange={onOpenChange}
        anchor={SCOPE_ANCHOR}
        budget={SCOPE_BUDGET}
      />
    );

    await user.clear(amountInput());
    await user.type(amountInput(), "999");
    await user.keyboard("{Escape}");
    expect(onOpenChange).toHaveBeenCalledWith(false);

    rerender(
      <SetBudgetDialog
        open={false}
        onOpenChange={onOpenChange}
        anchor={SCOPE_ANCHOR}
        budget={SCOPE_BUDGET}
      />
    );
    rerender(
      <SetBudgetDialog
        open
        onOpenChange={onOpenChange}
        anchor={SCOPE_ANCHOR}
        budget={SCOPE_BUDGET}
      />
    );

    expect(amountInput()).toHaveValue("10000.00");
  });
});
