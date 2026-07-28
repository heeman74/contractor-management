import React from "react";
import { render, screen } from "@testing-library/react";
import {
  BudgetSummarySection,
  formatPercentUsed,
} from "../components/BudgetSummarySection";
import { CostBreakdownSummary } from "../components/CostBreakdownSummary";
import type { BudgetVsActual, CostBreakdown } from "../types";

const UNDER_BUDGET: BudgetVsActual = {
  budgetId: "b-1",
  total: "10000.00",
  spent: "4200.00",
  remaining: "5800.00",
  percentUsed: "42.0",
};

function budgetWith(overrides: Partial<BudgetVsActual> = {}): BudgetVsActual {
  return { ...UNDER_BUDGET, ...overrides };
}

describe("BudgetSummarySection", () => {
  test("state 1/9: renders nothing when budget is null", () => {
    const { container } = render(<BudgetSummarySection budget={null} />);
    expect(container.firstChild).toBeNull();
  });

  test("renders nothing when budget is undefined", () => {
    const { container } = render(<BudgetSummarySection budget={undefined} />);
    expect(container.firstChild).toBeNull();
  });

  test("state 3: under 80% renders the plain triad with the dotted spent figure", () => {
    render(<BudgetSummarySection budget={budgetWith()} />);

    expect(screen.getByTestId("budget-section")).toBeInTheDocument();
    expect(screen.getByText("Budget")).toBeInTheDocument();
    expect(screen.getByText("Spent")).toBeInTheDocument();
    expect(screen.getByText("Remaining")).toBeInTheDocument();
    expect(screen.getByTestId("budget-amount")).toHaveTextContent("$10000.00");
    expect(screen.getByTestId("budget-spent").textContent).toBe("$4200.00 · 42%");
    expect(screen.getByTestId("budget-remaining")).toHaveTextContent("$5800.00");
    expect(screen.queryByTestId("budget-warning-chip")).not.toBeInTheDocument();
    expect(screen.getByTestId("budget-remaining")).not.toHaveClass("text-destructive");
  });

  test("state 4: warning band shows the amber chip left of the Remaining amount", () => {
    render(
      <BudgetSummarySection
        budget={budgetWith({ spent: "8200.00", remaining: "1800.00", percentUsed: "82.0" })}
      />
    );

    const chip = screen.getByTestId("budget-warning-chip");
    const figure = screen.getByTestId("budget-remaining");
    expect(chip).toHaveTextContent("Nearing budget");
    expect(
      chip.compareDocumentPosition(figure) & Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy();
    expect(figure).not.toHaveClass("text-destructive");
  });

  test("state 5: exactly at budget renders $0.00 plain with no chip and 100%", () => {
    render(
      <BudgetSummarySection
        budget={budgetWith({ spent: "10000.00", remaining: "0.00", percentUsed: "100.0" })}
      />
    );

    expect(screen.getByTestId("budget-spent").textContent).toBe("$10000.00 · 100%");
    expect(screen.getByTestId("budget-remaining")).toHaveTextContent("$0.00");
    expect(screen.getByTestId("budget-remaining")).not.toHaveClass("text-destructive");
    expect(screen.queryByTestId("budget-warning-chip")).not.toBeInTheDocument();
  });

  test("state 6: over budget renders the red signed negative with no chip", () => {
    render(
      <BudgetSummarySection
        budget={budgetWith({
          spent: "11200.00",
          remaining: "-1200.00",
          percentUsed: "112.0",
        })}
      />
    );

    const figure = screen.getByTestId("budget-remaining");
    expect(figure.textContent).toBe("-$1200.00");
    expect(figure).toHaveClass("text-destructive");
    expect(screen.getByTestId("budget-spent").textContent).toBe("$11200.00 · 112%");
    expect(screen.queryByTestId("budget-warning-chip")).not.toBeInTheDocument();
  });

  test("a fractional percent keeps its decimal — only a trailing .0 is dropped", () => {
    render(
      <BudgetSummarySection
        budget={budgetWith({ spent: "8250.00", remaining: "1750.00", percentUsed: "82.5" })}
      />
    );

    expect(screen.getByTestId("budget-spent").textContent).toBe("$8250.00 · 82.5%");
  });

  test("only the Remaining amount carries font-semibold", () => {
    render(<BudgetSummarySection budget={budgetWith()} />);

    expect(screen.getByTestId("budget-remaining")).toHaveClass("font-semibold");
    expect(screen.getByTestId("budget-amount")).not.toHaveClass("font-semibold");
    expect(screen.getByTestId("budget-spent")).not.toHaveClass("font-semibold");
  });
});

function breakdownWithBudget(
  overrides: Partial<CostBreakdown> = {}
): CostBreakdown {
  return {
    categories: [
      { categoryId: "c-materials", categoryName: "materials", total: "4200.00" },
    ],
    labor: null,
    laborTrackedAtJobLevel: true,
    grandTotal: "4200.00",
    margin: {
      revenue: "20000.00",
      revenueBasis: "invoiced",
      margin: "15800.00",
      marginPercent: "79.0",
      incomplete: false,
      incompleteReasons: [],
    },
    budget: budgetWith(),
    ...overrides,
  };
}

describe("CostBreakdownSummary budget wiring", () => {
  test.each(["project", "trade-scope"] as const)(
    "%s variant renders the budget rows between the Total row and the margin section",
    (variant) => {
      render(
        <CostBreakdownSummary breakdown={breakdownWithBudget()} variant={variant} />
      );

      const grandTotal = screen.getByTestId("breakdown-grand-total");
      const budgetSection = screen.getByTestId("budget-section");
      const marginSection = screen.getByTestId("margin-section");
      expect(
        grandTotal.compareDocumentPosition(budgetSection) &
          Node.DOCUMENT_POSITION_FOLLOWING
      ).toBeTruthy();
      expect(
        budgetSection.compareDocumentPosition(marginSection) &
          Node.DOCUMENT_POSITION_FOLLOWING
      ).toBeTruthy();
    }
  );

  test("state 10: job variant never renders budget rows even with budget data", () => {
    render(<CostBreakdownSummary breakdown={breakdownWithBudget()} variant="job" />);

    expect(screen.queryByTestId("budget-section")).not.toBeInTheDocument();
  });

  test("state 7: loading renders no budget rows even with stale data present", () => {
    render(
      <CostBreakdownSummary
        breakdown={breakdownWithBudget()}
        variant="trade-scope"
        isLoading
      />
    );

    expect(screen.queryByTestId("budget-section")).not.toBeInTheDocument();
  });

  test("state 8: error renders only the inherited error line, no budget rows", () => {
    render(
      <CostBreakdownSummary
        breakdown={breakdownWithBudget()}
        variant="trade-scope"
        isError
      />
    );

    expect(
      screen.getByText("Couldn't load cost breakdown. Refresh to try again.")
    ).toBeInTheDocument();
    expect(screen.queryByTestId("budget-section")).not.toBeInTheDocument();
  });

  test("a budget on an otherwise-empty breakdown still renders the summary", () => {
    render(
      <CostBreakdownSummary
        breakdown={breakdownWithBudget({
          categories: [],
          grandTotal: "0.00",
          margin: null,
        })}
        variant="trade-scope"
      />
    );

    expect(screen.getByTestId("budget-section")).toBeInTheDocument();
  });
});

describe("formatPercentUsed", () => {
  test.each([
    ["82.0", "82"],
    ["82.5", "82.5"],
    ["100.0", "100"],
    ["112.0", "112"],
    ["0.0", "0"],
  ])("formats %s as %s", (input, expected) => {
    expect(formatPercentUsed(input)).toBe(expected);
  });
});
