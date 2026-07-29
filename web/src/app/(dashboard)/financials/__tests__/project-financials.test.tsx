import React from "react";
import { fireEvent, render, screen, within } from "@testing-library/react";

import ProjectFinancialsDashboard from "../[projectId]/_components/project-financials-dashboard";
import {
  MarginTrendChart,
  toTrendData,
  trendCsvRows,
  trendMonthsKpi,
} from "../[projectId]/_components/margin-trend-chart";
import { TrendWindowFilter } from "../[projectId]/_components/trend-window-filter";
import {
  ScopeBudgetBars,
  budgetedScopesKpi,
  scopeBarsCsvRows,
  toScopeBarRows,
} from "../[projectId]/_components/scope-budget-bars";
import {
  CategoryMixChart,
  categoryMixCsvRows,
  categoryMixKpi,
  categoryTooltipDetail,
  toCategorySlices,
} from "../[projectId]/_components/category-mix-chart";
import { useProjectFinancials, useProjectMarginTrend } from "@/features/finance/hooks";
import { NO_REVENUE_NOTE } from "@/features/finance/components/MarginSummarySection";
import { CATEGORY_FILL } from "@/components/shared/chart-theme";
import { ApiError } from "@/lib/api-client";
import type {
  BudgetVsActual,
  CategoryTotal,
  CostBreakdown,
  LaborCostSummary,
  MarginSummary,
  MarginTrend,
  ProjectFinancials,
  ScopeBudgetRow,
  TrendBucket,
} from "@/features/finance/types";

jest.mock("@/features/finance/hooks", () => ({
  useProjectFinancials: jest.fn(),
  useProjectMarginTrend: jest.fn(),
}));
jest.mock("sonner", () => ({ toast: { error: jest.fn(), success: jest.fn() } }));
jest.mock("next/navigation", () => ({ useRouter: () => ({ push: jest.fn() }) }));

/**
 * Recharts' ResponsiveContainer measures the DOM, which jsdom cannot do, so it is
 * replaced by a fixed-size box that also exposes the computed plot height.
 */
jest.mock("recharts", () => {
  const actual = jest.requireActual("recharts");
  return {
    ...actual,
    ResponsiveContainer: ({
      children,
      height,
    }: {
      children: React.ReactElement;
      height: number;
    }) => (
      <div data-testid="responsive-container" data-height={height}>
        {React.cloneElement(children, {
          width: 800,
          height,
        } as Record<string, unknown>)}
      </div>
    ),
  };
});

const mockUseProjectFinancials = useProjectFinancials as jest.Mock;
const mockUseProjectMarginTrend = useProjectMarginTrend as jest.Mock;

const PROJECT_ID = "p-1";

const INVOICED_MARGIN: MarginSummary = {
  revenue: "100000.00",
  revenueBasis: "invoiced",
  margin: "21000.00",
  marginPercent: "21.0",
  incomplete: false,
  incompleteReasons: [],
};

function marginWith(overrides: Partial<MarginSummary> = {}): MarginSummary {
  return { ...INVOICED_MARGIN, ...overrides };
}

function breakdownWith(overrides: Partial<CostBreakdown> = {}): CostBreakdown {
  return {
    categories: [{ categoryId: "c-1", categoryName: "Materials", total: "30000.00" }],
    labor: { total: "49000.00", ratedSeconds: 3600, unratedSeconds: 0, basis: "unburdened" },
    laborTrackedAtJobLevel: true,
    grandTotal: "79000.00",
    margin: INVOICED_MARGIN,
    budget: null,
    ...overrides,
  };
}

function projectWith(overrides: Partial<ProjectFinancials> = {}): ProjectFinancials {
  return {
    projectId: PROJECT_ID,
    name: "Harbour Fitout",
    status: "active",
    breakdown: breakdownWith(),
    scopes: [],
    ...overrides,
  };
}

function trendWith(overrides: Partial<MarginTrend> = {}): MarginTrend {
  return { projectId: PROJECT_ID, window: "12m", buckets: [], ...overrides };
}

function mockQueries(
  financials: Partial<{
    data: ProjectFinancials;
    isLoading: boolean;
    isError: boolean;
    error: unknown;
  }>,
  trend: Partial<{ data: MarginTrend; isLoading: boolean; isFetching: boolean }> = {}
) {
  mockUseProjectFinancials.mockReturnValue({
    data: undefined,
    isLoading: false,
    isError: false,
    error: null,
    ...financials,
  });
  mockUseProjectMarginTrend.mockReturnValue({
    data: trendWith(),
    isLoading: false,
    isFetching: false,
    ...trend,
  });
}

function renderDashboard() {
  return render(<ProjectFinancialsDashboard projectId={PROJECT_ID} />);
}

beforeEach(() => {
  mockUseProjectFinancials.mockReset();
  mockUseProjectMarginTrend.mockReset();
});

// --- Task 1: drill-down shell, container and header states ---

describe("ProjectFinancialsDashboard shell", () => {
  it("state 21: renders the drill-down skeleton while the project query is loading", () => {
    mockQueries({ isLoading: true });

    renderDashboard();

    expect(screen.getByTestId("financials-skeleton")).toBeInTheDocument();
    expect(screen.queryByTestId("project-revenue")).not.toBeInTheDocument();
  });

  it("state 21: renders the skeleton while only the trend query is loading", () => {
    mockQueries({ data: projectWith() }, { data: undefined, isLoading: true });

    renderDashboard();

    expect(screen.getByTestId("financials-skeleton")).toBeInTheDocument();
  });

  it("state 22: a 404 renders the not-found panel with a link back to Financials", () => {
    mockQueries({ isError: true, error: new ApiError(404, "Project not found") });

    renderDashboard();

    const panel = screen.getByTestId("project-financials-not-found");
    expect(panel).toHaveTextContent("Project not found.");
    expect(within(panel).getByText("Back to Financials")).toHaveAttribute(
      "href",
      "/financials"
    );
    expect(screen.queryByTestId("financials-error")).not.toBeInTheDocument();
  });

  it("state 23: any other error renders the inline error panel, not the not-found panel", () => {
    mockQueries({ isError: true, error: new ApiError(500, "Server error") });

    renderDashboard();

    expect(screen.getByTestId("financials-error")).toHaveTextContent(
      "Couldn't load financials. Refresh to try again."
    );
    expect(screen.queryByTestId("project-financials-not-found")).not.toBeInTheDocument();
  });

  it("renders the back link, project name, status badge and subtitle on success", () => {
    mockQueries({ data: projectWith() });

    renderDashboard();

    const backLink = screen.getByLabelText("Back to Financials");
    expect(backLink).toHaveTextContent("← Financials");
    expect(backLink).toHaveAttribute("href", "/financials");
    expect(screen.getByRole("heading", { level: 1 })).toHaveTextContent("Harbour Fitout");
    expect(screen.getByText("active")).toBeInTheDocument();
    expect(screen.getByText("Margin, budget and cost detail.")).toBeInTheDocument();
  });

  it("reuses the shared tiles with drill-down titles and no portfolio-only chip", () => {
    mockQueries({ data: projectWith() });

    renderDashboard();

    expect(screen.getByText("Revenue")).toBeInTheDocument();
    expect(screen.getByText("Cost")).toBeInTheDocument();
    expect(screen.getByText("Margin")).toBeInTheDocument();
    expect(screen.getByTestId("project-revenue")).toHaveTextContent("$100000.00");
    expect(screen.getByTestId("project-cost")).toHaveTextContent("$79000.00");
    expect(screen.getByTestId("project-margin")).toHaveTextContent("$21000.00");
    expect(screen.queryByTestId("project-incomplete-badge")).not.toBeInTheDocument();
  });

  it("a null margin renders em dash tiles while cost still renders the grand total", () => {
    mockQueries({ data: projectWith({ breakdown: breakdownWith({ margin: null }) }) });

    renderDashboard();

    expect(screen.getByTestId("project-revenue")).toHaveTextContent("—");
    expect(screen.getByTestId("project-margin")).toHaveTextContent("—");
    expect(screen.getByTestId("project-cost")).toHaveTextContent("$79000.00");
    expect(screen.queryByTestId("project-margin-percent")).not.toBeInTheDocument();
    expect(screen.queryByText("$0.00")).not.toBeInTheDocument();
  });

  it("a null-revenue margin keeps the revenue tile honest rather than zero", () => {
    mockQueries({
      data: projectWith({
        breakdown: breakdownWith({
          margin: marginWith({
            revenue: null,
            revenueBasis: "none",
            margin: null,
            marginPercent: null,
          }),
        }),
      }),
    });

    renderDashboard();

    expect(screen.getByTestId("project-revenue")).toHaveTextContent("—");
    expect(screen.getByTestId("project-revenue-basis")).toHaveTextContent(
      "No revenue recorded yet."
    );
  });
});

// --- Task 2: margin trend and the window selector ---

function bucketOf(
  month: string,
  cost: string,
  margin: Partial<MarginSummary> = {}
): TrendBucket {
  return { month, cost, margin: marginWith(margin) };
}

const THREE_MONTH_TREND: TrendBucket[] = [
  bucketOf("2026-01", "10000.00", { revenue: "14000.00", margin: "4000.00", marginPercent: "28.6" }),
  bucketOf("2026-02", "12000.00", {
    revenue: null,
    revenueBasis: "none",
    margin: null,
    marginPercent: null,
  }),
  bucketOf("2026-03", "16000.00", { revenue: "12000.00", margin: "-4000.00", marginPercent: "-33.3" }),
];

function renderTrendCard(buckets: TrendBucket[], trend: Record<string, unknown> = {}) {
  mockQueries({ data: projectWith() }, { data: trendWith({ buckets }), ...trend });
  return renderDashboard();
}

function lineCurvePaths(container: HTMLElement): string[] {
  return Array.from(container.querySelectorAll(".recharts-line-curve")).map(
    (curve) => curve.getAttribute("d") ?? ""
  );
}

function axisTickLabels(container: HTMLElement): string[] {
  return Array.from(
    container.querySelectorAll(".recharts-cartesian-axis-tick-value")
  ).map((tick) => tick.textContent ?? "");
}

describe("MarginTrendChart series", () => {
  it("state 24: renders the three series and the months kpi", () => {
    const { container } = renderTrendCard(THREE_MONTH_TREND);

    expect(lineCurvePaths(container)).toHaveLength(3);
    const card = screen.getByLabelText("Margin Trend chart");
    expect(within(card).getByText("Margin Trend")).toBeInTheDocument();
    expect(within(card).getByText("3 months")).toBeInTheDocument();
    expect(trendMonthsKpi(THREE_MONTH_TREND.slice(0, 1))).toBe("1 month");
  });

  it("state 26: a null margin maps to null and renders a gap, never a $0 point", () => {
    const { container } = renderTrendCard(THREE_MONTH_TREND);

    const data = toTrendData(THREE_MONTH_TREND);
    expect(data[1].margin).toBeNull();
    expect(data[1].marginLabel).toBeNull();
    expect(data[1].revenue).toBeNull();
    expect(data[0].margin).toBe(4000);

    // connectNulls stays false, so the margin series is drawn as two sub-paths.
    const marginCurve = lineCurvePaths(container).at(-1) ?? "";
    expect(marginCurve.match(/M/g)).toHaveLength(2);
    expect(screen.queryByText("$0.00")).not.toBeInTheDocument();
  });

  it("labels every figure from the backend string, and the cost series never goes null", () => {
    const data = toTrendData(THREE_MONTH_TREND);

    expect(data[0].revenueLabel).toBe("$14000.00");
    expect(data[0].marginLabel).toBe("$4000.00");
    expect(data[0].marginPercentLabel).toBe("28.6%");
    expect(data[2].marginLabel).toBe("-$4000.00");
    expect(data[1].costLabel).toBe("$12000.00");
    expect(data[1].cost).toBe(12000);
  });

  it("formats the month axis by string split and the value axis with a leading sign", () => {
    const { container } = renderTrendCard(THREE_MONTH_TREND);

    const ticks = axisTickLabels(container);
    expect(ticks).toContain("Jan 26");
    expect(ticks).toContain("Mar 26");
    expect(ticks.some((tick) => /^-\$\d+k$/.test(tick))).toBe(true);
  });

  it("renders the break-even reference line label", () => {
    renderTrendCard(THREE_MONTH_TREND);

    expect(screen.getByText("Break-even")).toBeInTheDocument();
  });

  it("state 28: a window refetch keeps the previous chart on screen, dimmed and busy", () => {
    renderTrendCard(THREE_MONTH_TREND, { isFetching: true });

    const chart = screen.getByTestId("margin-trend-chart");
    expect(chart).toHaveClass("opacity-60");
    expect(chart).toHaveAttribute("aria-busy", "true");
    expect(screen.queryByTestId("financials-skeleton")).not.toBeInTheDocument();
  });

  it("state 27: every bucket without revenue renders the shipped no-revenue note", () => {
    renderTrendCard([
      bucketOf("2026-01", "10000.00", {
        revenue: null,
        revenueBasis: "none",
        margin: null,
        marginPercent: null,
      }),
    ]);

    expect(screen.getByTestId("trend-no-revenue-note")).toHaveTextContent(NO_REVENUE_NOTE);
  });

  it("state 27: one bucket with revenue suppresses the no-revenue note", () => {
    renderTrendCard(THREE_MONTH_TREND);

    expect(screen.queryByTestId("trend-no-revenue-note")).not.toBeInTheDocument();
  });

  it("state 25: zero buckets render the no-dated-records empty state", () => {
    renderTrendCard([]);

    expect(screen.getByText("No dated financial records yet")).toBeInTheDocument();
    expect(
      screen.getByText(
        "Costs, tracked time, invoices and approved quotes appear here once they carry dates."
      )
    ).toBeInTheDocument();
    expect(screen.queryByTestId("margin-trend-chart")).not.toBeInTheDocument();
  });

  it("exports empty CSV cells for a null month, never a zero", () => {
    const rows = trendCsvRows(THREE_MONTH_TREND);

    expect(rows[0]).toEqual([
      "Month",
      "Revenue",
      "Cost",
      "Margin",
      "Margin %",
      "Revenue basis",
    ]);
    expect(rows[2]).toEqual(["2026-02", "", "12000.00", "", "", "none"]);
    expect(rows[1]).toEqual([
      "2026-01",
      "14000.00",
      "10000.00",
      "4000.00",
      "28.6",
      "invoiced",
    ]);
  });

  it("renders standalone without a query client, taking already-parsed buckets", () => {
    render(<MarginTrendChart buckets={THREE_MONTH_TREND} isRefetching={false} />);

    expect(screen.getByTestId("margin-trend-chart")).toHaveAttribute("aria-busy", "false");
  });
});

describe("TrendWindowFilter", () => {
  it("renders the four window buttons with the active one pressed", () => {
    render(<TrendWindowFilter window="12m" onWindowChange={jest.fn()} />);

    expect(screen.getByTestId("trend-window-3m")).toHaveTextContent("Last 3m");
    expect(screen.getByTestId("trend-window-6m")).toHaveTextContent("Last 6m");
    expect(screen.getByTestId("trend-window-12m")).toHaveTextContent("Last 12m");
    expect(screen.getByTestId("trend-window-all")).toHaveTextContent("All time");
    expect(screen.getByTestId("trend-window-12m")).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByTestId("trend-window-3m")).toHaveAttribute("aria-pressed", "false");
  });

  it("reports the clicked window once and changes nothing else", () => {
    const onWindowChange = jest.fn();
    render(<TrendWindowFilter window="12m" onWindowChange={onWindowChange} />);

    fireEvent.click(screen.getByTestId("trend-window-3m"));

    expect(onWindowChange).toHaveBeenCalledTimes(1);
    expect(onWindowChange).toHaveBeenCalledWith("3m");
  });
});

describe("Margin Trend card wiring", () => {
  it("renders the selector, then the cumulative caption, then the plot", () => {
    renderTrendCard(THREE_MONTH_TREND);

    const card = screen.getByLabelText("Margin Trend chart");
    expect(within(card).getByTestId("trend-window-note")).toHaveTextContent(
      "Cumulative from project start — the window only changes how far back the chart shows."
    );
    expect(within(card).getByTestId("trend-window-12m")).toBeInTheDocument();
    expect(within(card).getByTestId("margin-trend-chart")).toBeInTheDocument();
  });

  it("state 28: switching the window refetches only the trend query", () => {
    renderTrendCard(THREE_MONTH_TREND);
    const financialsCallsBefore = mockUseProjectFinancials.mock.calls.length;

    fireEvent.click(screen.getByTestId("trend-window-3m"));

    expect(mockUseProjectMarginTrend).toHaveBeenLastCalledWith(PROJECT_ID, "3m");
    expect(
      mockUseProjectFinancials.mock.calls.slice(financialsCallsBefore)
    ).toEqual([[PROJECT_ID]]);
    expect(screen.getByTestId("trend-window-3m")).toHaveAttribute("aria-pressed", "true");
  });
});

// --- Task 3: scope budget bars and the cost category mix ---

function scopeRow(
  tradeScopeId: string,
  tradeName: string,
  budget: BudgetVsActual | null
): ScopeBudgetRow {
  return { tradeScopeId, tradeName, spent: budget?.spent ?? "0.00", budget };
}

function budgetOf(total: string, spent: string): BudgetVsActual {
  return {
    budgetId: `budget-${total}-${spent}`,
    total,
    spent,
    remaining: (Number(total) - Number(spent)).toFixed(2),
    percentUsed: ((Number(spent) / Number(total)) * 100).toFixed(1),
  };
}

function categoryOf(categoryName: string, total: string): CategoryTotal {
  return { categoryId: `cat-${categoryName}`, categoryName, total };
}

function laborOf(total: string): LaborCostSummary {
  return { total, ratedSeconds: 7200, unratedSeconds: 0, basis: "unburdened" };
}

const SCOPE_LABOR_NOTE = "Scope spend excludes labor — labor is tracked at job level.";

function categoryAxisLabels(container: HTMLElement): string[] {
  return axisTickLabels(container).filter((label) => !/^\d+%$/.test(label));
}

function pieSectorFills(container: HTMLElement): string[] {
  return Array.from(container.querySelectorAll("path.recharts-sector")).map(
    (sector) => sector.getAttribute("fill") ?? ""
  );
}

function pieLabelTexts(container: HTMLElement): string[] {
  return Array.from(container.querySelectorAll(".recharts-pie-label-text")).map(
    (label) => label.textContent ?? ""
  );
}

describe("ScopeBudgetBars", () => {
  it("state 30: renders the shared bullet-bar form with the labor caption", () => {
    const scopes = [
      scopeRow("s-1", "Electrical", budgetOf("10000.00", "8500.00")),
      scopeRow("s-2", "Plumbing", budgetOf("4000.00", "1000.00")),
    ];

    const { container } = render(<ScopeBudgetBars scopes={scopes} />);

    expect(screen.getByTestId("scope-budget-bars")).toBeInTheDocument();
    expect(categoryAxisLabels(container)).toEqual(["Electrical", "Plumbing"]);
    expect(screen.getByTestId("scope-labor-note")).toHaveTextContent(SCOPE_LABOR_NOTE);
    expect(budgetedScopesKpi(scopes)).toBe("2 of 2 scopes budgeted");
  });

  it("sorts scopes descending by the true percent used and keys rows by trade name", () => {
    const rows = toScopeBarRows([
      scopeRow("s-1", "Plumbing", budgetOf("10000.00", "1000.00")),
      scopeRow("s-2", "Electrical", budgetOf("1000.00", "1400.00")),
      scopeRow("s-3", "Framing", null),
    ]);

    expect(rows.map((row) => row.label)).toEqual(["Electrical", "Plumbing"]);
    expect(rows[0].id).toBe("s-2");
    expect(rows[0].percentUsed).toBe("140.0");
    expect(rows[0].spentLabel).toBe("$1400.00");
    expect(rows[0].budgetLabel).toBe("$1000.00");
  });

  it("attaches no click-through, because no per-scope financial route exists", () => {
    const { container } = render(
      <ScopeBudgetBars scopes={[scopeRow("s-1", "Electrical", budgetOf("1000.00", "400.00"))]} />
    );

    const bars = container.querySelectorAll("path.recharts-rectangle");
    expect(bars.length).toBeGreaterThan(0);
    bars.forEach((bar) => expect(bar.getAttribute("cursor")).not.toBe("pointer"));
  });

  it("state 31: no scope budget renders the empty state and hides the labor caption", () => {
    render(<ScopeBudgetBars scopes={[scopeRow("s-1", "Framing", null)]} />);

    expect(screen.getByText("No scope budgets set")).toBeInTheDocument();
    expect(
      screen.getByText("Set a budget on a trade scope to track its spend.")
    ).toBeInTheDocument();
    expect(screen.queryByTestId("scope-labor-note")).not.toBeInTheDocument();
    expect(screen.queryByTestId("scope-budget-bars")).not.toBeInTheDocument();
  });

  it("exports full trade names and the true percent", () => {
    const rows = scopeBarsCsvRows([
      scopeRow("s-1", "Electrical", budgetOf("500.00", "1700.00")),
      scopeRow("s-2", "Framing", null),
    ]);

    expect(rows[0]).toEqual(["Trade scope", "Budget", "Spent", "Percent used"]);
    expect(rows[1]).toEqual(["Electrical", "500.00", "1700.00", "340.0"]);
    expect(rows).toHaveLength(2);
    expect(budgetedScopesKpi([scopeRow("s-1", "Electrical", null)])).toBe(
      "0 of 1 scopes budgeted"
    );
  });
});

describe("CategoryMixChart", () => {
  const FOUR_CATEGORIES = [
    categoryOf("Materials", "30000.00"),
    categoryOf("Subcontractor", "12000.00"),
    categoryOf("Other", "6000.00"),
    categoryOf("Permits", "2000.00"),
  ];

  it("state 32: prepends labor, sorts descending and fills from the nominal ramp", () => {
    const { container } = render(
      <CategoryMixChart categories={FOUR_CATEGORIES} labor={laborOf("49000.00")} />
    );

    const slices = toCategorySlices(FOUR_CATEGORIES, laborOf("49000.00"));
    expect(slices.map((slice) => slice.name)).toEqual([
      "Labor",
      "Materials",
      "Subcontractor",
      "Permits",
      "Other",
    ]);
    const fills = pieSectorFills(container);
    expect(fills[0]).toBe(CATEGORY_FILL.labor);
    expect(fills[1]).toBe(CATEGORY_FILL.materials);
    expect(new Set(fills).size).toBe(fills.length);
    expect(screen.getByTestId("category-mix-chart")).toBeInTheDocument();
  });

  it("state 33: seven categories cap at six slices with Other last and named", () => {
    const seven = [
      categoryOf("Materials", "30000.00"),
      categoryOf("Subcontractor", "12000.00"),
      categoryOf("Equipment", "9000.00"),
      categoryOf("Permits", "5000.00"),
      categoryOf("Disposal", "3000.00"),
      categoryOf("Signage", "2000.00"),
      categoryOf("Fuel", "1000.00"),
    ];

    const { container } = render(<CategoryMixChart categories={seven} labor={null} />);

    const slices = toCategorySlices(seven, null);
    expect(slices).toHaveLength(6);
    expect(slices.at(-1)?.name).toBe("Other");
    expect(slices.at(-1)?.rolledUpNames).toEqual(["Signage", "Fuel"]);
    expect(slices.at(-1)?.amount).toBe(3000);
    expect(pieSectorFills(container)).toHaveLength(6);
    expect(new Set(pieSectorFills(container)).size).toBe(6);
  });

  it("state 33: the Other tooltip names what was rolled up, and the CSV rolls nothing up", () => {
    const seven = [
      categoryOf("Materials", "30000.00"),
      categoryOf("Subcontractor", "12000.00"),
      categoryOf("Equipment", "9000.00"),
      categoryOf("Permits", "5000.00"),
      categoryOf("Disposal", "3000.00"),
      categoryOf("Signage", "2000.00"),
      categoryOf("Fuel", "1000.00"),
    ];
    const slices = toCategorySlices(seven, null);

    expect(categoryTooltipDetail(slices[0], 62000)).toBe("$30000.00 (48.4%)");
    expect(categoryTooltipDetail(slices.at(-1)!, 62000)).toContain("Signage, Fuel");

    const rows = categoryMixCsvRows(seven, null);
    expect(rows[0]).toEqual(["Category", "Amount", "Percent of total"]);
    expect(rows).toHaveLength(8);
    expect(rows.map((row) => row[0])).toContain("Fuel");
    expect(rows.map((row) => row[0])).not.toContain("Other");
  });

  it("includes labor as its own CSV row using the backend string", () => {
    const rows = categoryMixCsvRows([categoryOf("Materials", "30000.00")], laborOf("10000.00"));

    expect(rows[1]).toEqual(["Labor", "10000.00", "25"]);
    expect(rows[2]).toEqual(["Materials", "30000.00", "75"]);
  });

  it("suppresses on-slice labels below the collision threshold", () => {
    const { container } = render(
      <CategoryMixChart
        categories={[categoryOf("Materials", "99000.00"), categoryOf("Permits", "1000.00")]}
        labor={null}
      />
    );

    const labels = pieLabelTexts(container);
    expect(labels).toContain("Materials 99%");
    expect(labels.filter((label) => label === "")).toHaveLength(1);
  });

  it("state 34: no costs and no labor render the no-costs empty state", () => {
    render(<CategoryMixChart categories={[]} labor={null} />);

    expect(screen.getByText("No costs recorded")).toBeInTheDocument();
    expect(
      screen.getByText("Add a cost entry or tracked time to see where the money goes.")
    ).toBeInTheDocument();
    expect(screen.queryByTestId("category-mix-chart")).not.toBeInTheDocument();
  });

  it("states the total cost in the card kpi", () => {
    expect(categoryMixKpi("40120.00")).toBe("$40120.00 total cost");
  });
});

describe("Scope and category card wiring", () => {
  it("renders both half-width cards with their titles, kpis and charts", () => {
    mockQueries({
      data: projectWith({
        scopes: [scopeRow("s-1", "Electrical", budgetOf("10000.00", "8500.00"))],
      }),
      });

    renderDashboard();

    const scopeCard = screen.getByLabelText("Budget vs Actual by Trade Scope chart");
    expect(within(scopeCard).getByText("Budget vs Actual by Trade Scope")).toBeInTheDocument();
    expect(within(scopeCard).getByText("1 of 1 scopes budgeted")).toBeInTheDocument();
    expect(within(scopeCard).getByTestId("scope-budget-bars")).toBeInTheDocument();
    expect(within(scopeCard).getByTestId("scope-labor-note")).toBeInTheDocument();

    const mixCard = screen.getByLabelText("Cost Category Mix chart");
    expect(within(mixCard).getByText("Cost Category Mix")).toBeInTheDocument();
    expect(within(mixCard).getByText("$79000.00 total cost")).toBeInTheDocument();
    expect(within(mixCard).getByTestId("category-mix-chart")).toBeInTheDocument();
  });
});
