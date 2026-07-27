import React from "react";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import {
  CostBreakdownSummary,
  displayCategoryName,
  formatUnratedHours,
  isBreakdownEmpty,
  orderedCategories,
} from "../components/CostBreakdownSummary";
import type { CategoryTotal, CostBreakdown } from "../types";

const MATERIALS: CategoryTotal = {
  categoryId: "c-materials",
  categoryName: "materials",
  total: "150.00",
};
const SUBCONTRACTOR: CategoryTotal = {
  categoryId: "c-sub",
  categoryName: "subcontractor",
  total: "200.00",
};

function breakdownWith(overrides: Partial<CostBreakdown> = {}): CostBreakdown {
  return {
    categories: [MATERIALS, SUBCONTRACTOR],
    labor: { total: "240.00", ratedSeconds: 28800, unratedSeconds: 0, basis: "unburdened" },
    laborTrackedAtJobLevel: false,
    grandTotal: "590.00",
    ...overrides,
  };
}

function laborWith(unratedSeconds: number) {
  return { total: "240.00", ratedSeconds: 28800, unratedSeconds, basis: "unburdened" };
}

describe("CostBreakdownSummary", () => {
  test("renders rows in fixed order with amounts and grand total", () => {
    render(<CostBreakdownSummary breakdown={breakdownWith()} variant="job" />);

    const root = screen.getByTestId("cost-breakdown");
    const labels = within(root)
      .getAllByText(/^(Labor|Materials|Subcontractor|Total)$/)
      .map((el) => el.textContent);
    expect(labels).toEqual(["Labor", "Materials", "Subcontractor", "Total"]);
    expect(screen.getByTestId("breakdown-labor-amount")).toHaveTextContent("$240.00");
    expect(within(root).getByText("$150.00")).toBeInTheDocument();
    expect(screen.getByTestId("breakdown-grand-total")).toHaveTextContent("$590.00");
  });

  test("shows the unrated badge with hours visible", () => {
    render(
      <CostBreakdownSummary
        breakdown={breakdownWith({ labor: laborWith(45000) })}
        variant="job"
      />
    );

    expect(screen.getByTestId("breakdown-unrated-badge")).toHaveTextContent(
      "12.5 hrs unrated"
    );
  });

  test("uses the singular form for exactly one unrated hour", () => {
    render(
      <CostBreakdownSummary
        breakdown={breakdownWith({ labor: laborWith(3600) })}
        variant="job"
      />
    );

    expect(screen.getByTestId("breakdown-unrated-badge")).toHaveTextContent(
      "1 hr unrated"
    );
  });

  test("drops the trailing .0 for whole unrated hours", () => {
    render(
      <CostBreakdownSummary
        breakdown={breakdownWith({ labor: laborWith(7200) })}
        variant="job"
      />
    );

    expect(screen.getByTestId("breakdown-unrated-badge")).toHaveTextContent(
      "2 hrs unrated"
    );
  });

  test("renders no unrated badge when all time is rated", () => {
    render(<CostBreakdownSummary breakdown={breakdownWith()} variant="job" />);

    expect(screen.queryByTestId("breakdown-unrated-badge")).not.toBeInTheDocument();
  });

  test("discloses the unburdened basis via the info popover", async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    render(<CostBreakdownSummary breakdown={breakdownWith()} variant="job" />);

    await user.click(screen.getByRole("button", { name: "About labor cost" }));

    expect(await screen.findByText("Unburdened labor")).toBeInTheDocument();
    expect(
      screen.getByText("Wage cost only — excludes payroll tax, insurance, overhead.")
    ).toBeInTheDocument();
  });

  test("trade-scope variant shows the job-level note instead of a labor amount", () => {
    render(
      <CostBreakdownSummary
        breakdown={breakdownWith({
          labor: null,
          laborTrackedAtJobLevel: true,
          grandTotal: "350.00",
        })}
        variant="trade-scope"
      />
    );

    expect(screen.getByText("Tracked at job level")).toBeInTheDocument();
    expect(screen.queryByTestId("breakdown-labor-amount")).not.toBeInTheDocument();
    expect(screen.queryByTestId("breakdown-unrated-badge")).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "About labor cost" })
    ).not.toBeInTheDocument();
  });

  test("renders em-dash amounts while loading", () => {
    render(<CostBreakdownSummary breakdown={undefined} variant="job" isLoading />);

    expect(screen.getByTestId("breakdown-labor-amount")).toHaveTextContent("—");
    expect(screen.getByTestId("breakdown-grand-total")).toHaveTextContent("—");
  });

  test("renders only the inline error line on fetch failure", () => {
    render(<CostBreakdownSummary breakdown={undefined} variant="job" isError />);

    expect(
      screen.getByText("Couldn't load cost breakdown. Refresh to try again.")
    ).toBeInTheDocument();
    expect(screen.queryByTestId("cost-breakdown")).not.toBeInTheDocument();
  });

  test("renders nothing when there is no cost data at all", () => {
    const { container } = render(
      <CostBreakdownSummary
        breakdown={{
          categories: [],
          labor: { total: "0.00", ratedSeconds: 0, unratedSeconds: 0, basis: "unburdened" },
          laborTrackedAtJobLevel: false,
          grandTotal: "0.00",
        }}
        variant="job"
      />
    );

    expect(container.firstChild).toBeNull();
  });

  test("never renders a second Labor row for a labor-named category", () => {
    render(
      <CostBreakdownSummary
        breakdown={breakdownWith({
          categories: [
            ...breakdownWith().categories,
            { categoryId: "c-labor", categoryName: "labor", total: "50.00" },
          ],
        })}
        variant="job"
      />
    );

    expect(screen.getAllByText("Labor")).toHaveLength(1);
  });
});

describe("formatUnratedHours", () => {
  test.each([
    [0, "0 hrs unrated"],
    [3600, "1 hr unrated"],
    [5400, "1.5 hrs unrated"],
    [7200, "2 hrs unrated"],
    [45000, "12.5 hrs unrated"],
  ])("formats %i seconds as %s", (seconds, expected) => {
    expect(formatUnratedHours(seconds)).toBe(expected);
  });
});

describe("orderedCategories", () => {
  test("filters labor, keeps fixed order, then customs alphabetically", () => {
    const shuffled: CategoryTotal[] = [
      { categoryId: "c-permits", categoryName: "permits", total: "10.00" },
      { categoryId: "c-other", categoryName: "other", total: "20.00" },
      { categoryId: "c-labor", categoryName: "labor", total: "30.00" },
      SUBCONTRACTOR,
      { categoryId: "c-equipment", categoryName: "equipment", total: "40.00" },
      MATERIALS,
    ];

    expect(orderedCategories(shuffled).map((c) => c.categoryName)).toEqual([
      "materials",
      "subcontractor",
      "other",
      "equipment",
      "permits",
    ]);
  });
});

describe("isBreakdownEmpty", () => {
  test("is true only when categories, grand total, and unrated time are all empty", () => {
    expect(isBreakdownEmpty(breakdownWith())).toBe(false);
    expect(
      isBreakdownEmpty(
        breakdownWith({ categories: [], labor: laborWith(3600), grandTotal: "0.00" })
      )
    ).toBe(false);
    expect(
      isBreakdownEmpty({
        categories: [],
        labor: { total: "0.00", ratedSeconds: 0, unratedSeconds: 0, basis: "unburdened" },
        laborTrackedAtJobLevel: false,
        grandTotal: "0.00",
      })
    ).toBe(true);
    expect(
      isBreakdownEmpty({
        categories: [],
        labor: null,
        laborTrackedAtJobLevel: true,
        grandTotal: "0.00",
      })
    ).toBe(true);
  });
});

describe("displayCategoryName", () => {
  test("title-cases the lowercase API name", () => {
    expect(displayCategoryName("materials")).toBe("Materials");
    expect(displayCategoryName("subcontractor")).toBe("Subcontractor");
  });
});
