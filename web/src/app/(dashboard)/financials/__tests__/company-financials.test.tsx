import React from "react";
import { render, screen, within } from "@testing-library/react";
import { toast } from "sonner";

import CompanyFinancialsDashboard from "../_components/company-financials-dashboard";
import { FinanceSummaryTiles } from "../_components/finance-summary-tiles";
import {
  ProjectBudgetBars,
  budgetBarsCsvRows,
  toBudgetBarRows,
} from "../_components/project-budget-bars";
import { AttentionList, attentionKpi } from "../_components/attention-list";
import { ProjectsTable, groupProjectsByActivity } from "../_components/projects-table";
import { useCompanyFinancials } from "@/features/finance/hooks";
import {
  INCOMPLETE_CAPTION,
  INCOMPLETE_CHIP_LABEL,
} from "@/features/finance/components/MarginSummarySection";
import { FINANCE_FLAG_CHIP_CLASS } from "@/features/finance/components/FinanceFlagChip";
import { BUDGET_TIER_FILL } from "@/components/shared/chart-theme";
import type {
  AttentionRow,
  AttentionTier,
  BudgetVsActual,
  CompanyFinancials,
  MarginSummary,
  PortfolioTotals,
  ProjectFinancialsRow,
} from "@/features/finance/types";

jest.mock("@/features/finance/hooks", () => ({ useCompanyFinancials: jest.fn() }));
jest.mock("sonner", () => ({ toast: { error: jest.fn(), success: jest.fn() } }));
jest.mock("next/navigation", () => ({ useRouter: () => ({ push: jest.fn() }) }));

/**
 * Recharts' ResponsiveContainer measures the DOM, which jsdom cannot do, so it is
 * replaced by a fixed-size box that also exposes the computed plot height — the
 * geometry contract (28px per row, no ceiling) is asserted through it.
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

const mockUseCompanyFinancials = useCompanyFinancials as jest.Mock;
const mockToastError = toast.error as jest.Mock;

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

function portfolioWith(overrides: Partial<PortfolioTotals> = {}): PortfolioTotals {
  return {
    cost: "79000.00",
    quotedRevenue: null,
    incompleteProjectCount: 0,
    margin: INVOICED_MARGIN,
    ...overrides,
  };
}

function financialsWith(overrides: Partial<CompanyFinancials> = {}): CompanyFinancials {
  return { portfolio: portfolioWith(), projects: [], attention: [], ...overrides };
}

function mockQueryState(
  state: Partial<{ data: CompanyFinancials; isLoading: boolean; isError: boolean }>
) {
  mockUseCompanyFinancials.mockReturnValue({
    data: undefined,
    isLoading: false,
    isError: false,
    ...state,
  });
}

function renderDashboardWithPortfolio(portfolio: PortfolioTotals) {
  mockQueryState({ data: financialsWith({ portfolio }) });
  return render(<CompanyFinancialsDashboard />);
}

beforeEach(() => {
  mockUseCompanyFinancials.mockReset();
  mockToastError.mockReset();
});

describe("CompanyFinancialsDashboard shell", () => {
  it("state 4: renders the company skeleton while the query is loading", () => {
    mockQueryState({ isLoading: true });

    render(<CompanyFinancialsDashboard />);

    expect(screen.getByTestId("financials-skeleton")).toBeInTheDocument();
    expect(screen.getByTestId("financials-skeleton-table")).toBeInTheDocument();
    expect(screen.queryByTestId("portfolio-revenue")).not.toBeInTheDocument();
  });

  it("state 5: replaces the body with the inline error panel and raises no toast", () => {
    mockQueryState({ isError: true });

    render(<CompanyFinancialsDashboard />);

    expect(screen.getByTestId("financials-error")).toHaveTextContent(
      "Couldn't load financials. Refresh to try again."
    );
    expect(screen.queryByTestId("portfolio-revenue")).not.toBeInTheDocument();
    expect(mockToastError).not.toHaveBeenCalled();
  });

  it("renders the three portfolio tile titles on success", () => {
    renderDashboardWithPortfolio(portfolioWith());

    expect(screen.getByText("Portfolio revenue")).toBeInTheDocument();
    expect(screen.getByText("Portfolio cost")).toBeInTheDocument();
    expect(screen.getByText("Portfolio margin")).toBeInTheDocument();
    expect(screen.getByTestId("portfolio-cost")).toHaveTextContent("$79000.00");
  });
});

describe("FinanceSummaryTiles revenue basis", () => {
  it("state 13: revenue basis none renders an em dash figure and the no-revenue caption", () => {
    renderDashboardWithPortfolio(
      portfolioWith({
        margin: marginWith({
          revenue: null,
          revenueBasis: "none",
          margin: null,
          marginPercent: null,
        }),
      })
    );

    expect(screen.getByTestId("portfolio-revenue")).toHaveTextContent("—");
    expect(screen.getByTestId("portfolio-revenue-basis")).toHaveTextContent(
      "No revenue recorded yet."
    );
    expect(screen.getByTestId("portfolio-margin")).toHaveTextContent("—");
    expect(screen.queryByTestId("portfolio-margin-percent")).not.toBeInTheDocument();
  });

  it("state 11: revenue basis mixed names the quoted share with no thousands separators", () => {
    renderDashboardWithPortfolio(
      portfolioWith({
        quotedRevenue: "18400.00",
        margin: marginWith({ revenueBasis: "mixed" }),
      })
    );

    expect(screen.getByTestId("portfolio-revenue-basis")).toHaveTextContent(
      "Includes $18400.00 from approved quotes — not yet invoiced."
    );
  });

  it("state 12: revenue basis quoted renders the approved-quotes caption", () => {
    renderDashboardWithPortfolio(
      portfolioWith({ margin: marginWith({ revenueBasis: "quoted" }) })
    );

    expect(screen.getByTestId("portfolio-revenue-basis")).toHaveTextContent(
      "Based on approved quotes — not yet invoiced."
    );
  });
});

describe("FinanceSummaryTiles incomplete-data badge", () => {
  it("state 9: three incomplete projects render the plural chip anchored to the attention list", () => {
    renderDashboardWithPortfolio(portfolioWith({ incompleteProjectCount: 3 }));

    const badge = screen.getByTestId("portfolio-incomplete-badge");
    expect(badge).toHaveTextContent("3 projects with incomplete data");
    expect(badge.closest("a")).toHaveAttribute("href", "#attention-list");
    expect(screen.getByTestId("portfolio-incomplete-caption")).toHaveTextContent(
      INCOMPLETE_CAPTION
    );
  });

  it("state 9: a single incomplete project renders the singular chip", () => {
    renderDashboardWithPortfolio(portfolioWith({ incompleteProjectCount: 1 }));

    expect(screen.getByTestId("portfolio-incomplete-badge")).toHaveTextContent(
      "1 project with incomplete data"
    );
  });

  it("state 10: a zero incomplete count renders neither chip nor caption", () => {
    renderDashboardWithPortfolio(portfolioWith({ incompleteProjectCount: 0 }));

    expect(screen.queryByTestId("portfolio-incomplete-badge")).not.toBeInTheDocument();
    expect(screen.queryByTestId("portfolio-incomplete-caption")).not.toBeInTheDocument();
  });
});

describe("FinanceSummaryTiles margin figure", () => {
  it("state 14: a negative portfolio margin renders destructive at tile size with its percent", () => {
    renderDashboardWithPortfolio(
      portfolioWith({
        margin: marginWith({ margin: "-3500.00", marginPercent: "-8.0" }),
      })
    );

    const figure = screen.getByTestId("portfolio-margin");
    expect(figure).toHaveTextContent("-$3500.00");
    expect(figure).toHaveClass("text-destructive");
    expect(figure).toHaveClass("text-3xl");
    expect(screen.getByTestId("portfolio-margin-percent")).toHaveTextContent("-8% margin");
  });

  it("reused without the portfolio-only props, a null margin renders em dashes and no chip", () => {
    render(
      <FinanceSummaryTiles
        revenueTitle="Revenue"
        costTitle="Cost"
        marginTitle="Margin"
        cost="40120.00"
        margin={null}
        testIdPrefix="project"
      />
    );

    expect(screen.getByTestId("project-revenue")).toHaveTextContent("—");
    expect(screen.getByTestId("project-margin")).toHaveTextContent("—");
    expect(screen.getByTestId("project-cost")).toHaveTextContent("$40120.00");
    expect(screen.queryByTestId("project-margin-percent")).not.toBeInTheDocument();
    expect(screen.queryByTestId("project-revenue-basis")).not.toBeInTheDocument();
    expect(screen.queryByTestId("project-incomplete-badge")).not.toBeInTheDocument();
    expect(screen.queryByTestId("project-incomplete-caption")).not.toBeInTheDocument();
  });
});

// --- Task 2: budget bullet bars ---

const BUDGETED_STATUS = "active";

function budgetOf(total: string, spent: string): BudgetVsActual {
  return {
    budgetId: `budget-${total}-${spent}`,
    total,
    spent,
    remaining: (Number(total) - Number(spent)).toFixed(2),
    percentUsed: ((Number(spent) / Number(total)) * 100).toFixed(1),
  };
}

function projectRow(
  projectId: string,
  name: string,
  budget: BudgetVsActual | null,
  status: string = BUDGETED_STATUS
): ProjectFinancialsRow {
  return {
    projectId,
    name,
    status,
    cost: budget?.spent ?? "0.00",
    margin: INVOICED_MARGIN,
    budget,
  };
}

function barFills(container: HTMLElement): string[] {
  return Array.from(container.querySelectorAll("path.recharts-rectangle")).map(
    (bar) => bar.getAttribute("fill") ?? ""
  );
}

function barFillOpacities(container: HTMLElement): string[] {
  return Array.from(container.querySelectorAll("path.recharts-rectangle")).map(
    (bar) => bar.getAttribute("fill-opacity") ?? ""
  );
}

const PERCENT_TICK = /^\d+%$/;

/** Recharts renders every axis tick label into a shared layer, so the two axes are
 *  told apart by their content: the value axis is percentages, the other is names. */
function axisTickLabels(container: HTMLElement): string[] {
  return Array.from(
    container.querySelectorAll(".recharts-cartesian-axis-tick-value")
  ).map((tick) => tick.textContent ?? "");
}

function categoryAxisLabels(container: HTMLElement): string[] {
  return axisTickLabels(container).filter((label) => !PERCENT_TICK.test(label));
}

function valueAxisLabels(container: HTMLElement): string[] {
  return axisTickLabels(container).filter((label) => PERCENT_TICK.test(label));
}

describe("ProjectBudgetBars", () => {
  it("state 8: only budgeted projects get a bar and the rest are named in the caption", () => {
    const { container } = render(
      <ProjectBudgetBars
        projects={[
          projectRow("p-1", "Harbour Fitout", budgetOf("10000.00", "4200.00")),
          projectRow("p-2", "Rooftop Deck", null),
          projectRow("p-3", "Lobby Refresh", null),
        ]}
      />
    );

    expect(categoryAxisLabels(container)).toEqual(["Harbour Fitout"]);
    expect(screen.getByTestId("project-budget-bars-unbudgeted-note")).toHaveTextContent(
      "2 projects have no budget set."
    );
  });

  it("state 8: a single unbudgeted project uses the singular caption", () => {
    render(
      <ProjectBudgetBars
        projects={[
          projectRow("p-1", "Harbour Fitout", budgetOf("10000.00", "4200.00")),
          projectRow("p-2", "Rooftop Deck", null),
        ]}
      />
    );

    expect(screen.getByTestId("project-budget-bars-unbudgeted-note")).toHaveTextContent(
      "1 project has no budget set."
    );
  });

  it("omits the caption entirely when every project is budgeted", () => {
    render(
      <ProjectBudgetBars
        projects={[projectRow("p-1", "Harbour Fitout", budgetOf("10000.00", "4200.00"))]}
      />
    );

    expect(
      screen.queryByTestId("project-budget-bars-unbudgeted-note")
    ).not.toBeInTheDocument();
  });

  it("sorts bars descending by the true percent used, worst at the top", () => {
    const projects = [
      projectRow("p-1", "Middle", budgetOf("10000.00", "9000.00")),
      projectRow("p-2", "Worst", budgetOf("1000.00", "5000.00")),
      projectRow("p-3", "Best", budgetOf("10000.00", "1000.00")),
    ];

    const { container } = render(<ProjectBudgetBars projects={projects} />);

    expect(toBudgetBarRows(projects).map((row) => row.label)).toEqual([
      "Worst",
      "Middle",
      "Best",
    ]);
    expect(categoryAxisLabels(container)).toEqual(["Worst", "Middle", "Best"]);
  });

  it("fills the three tier bands, and exactly 100% is not amber", () => {
    const { container } = render(
      <ProjectBudgetBars
        projects={[
          projectRow("p-over", "Over", budgetOf("1000.00", "1400.00")),
          projectRow("p-exact", "Exactly at budget", budgetOf("1000.00", "1000.00")),
          projectRow("p-warn", "Nearing", budgetOf("1000.00", "850.00")),
          projectRow("p-normal", "Normal", budgetOf("1000.00", "400.00")),
        ]}
      />
    );

    expect(barFills(container)).toEqual([
      BUDGET_TIER_FILL.over,
      BUDGET_TIER_FILL.normal,
      BUDGET_TIER_FILL.warning,
      BUDGET_TIER_FILL.normal,
    ]);
  });

  it("state 18: inactive-status projects keep their tier fill at reduced opacity", () => {
    const { container } = render(
      <ProjectBudgetBars
        projects={[
          projectRow("p-1", "Archived Job", budgetOf("1000.00", "400.00"), "archived"),
          projectRow("p-2", "Running Job", budgetOf("1000.00", "300.00"), "active"),
        ]}
      />
    );

    expect(barFillOpacities(container)).toEqual(["0.45", "1"]);
  });

  it("state 20: an extreme overrun is marked with its true percent, never silently truncated", () => {
    const projects = [
      projectRow("p-1", "Runaway", budgetOf("500.00", "1700.00")),
      projectRow("p-2", "Steady", budgetOf("1000.00", "400.00")),
    ];

    const { container } = render(<ProjectBudgetBars projects={projects} />);

    expect(screen.getByTestId("budget-bar-overflow-p-1")).toHaveTextContent("▸ 340%");
    expect(screen.queryByTestId("budget-bar-overflow-p-2")).not.toBeInTheDocument();
    expect(valueAxisLabels(container).at(-1)).toBe("200%");
    expect(budgetBarsCsvRows(projects)[1]).toEqual([
      "Runaway",
      "active",
      "500.00",
      "1700.00",
      "340.0",
    ]);
  });

  it("floors the axis at 120% so the budget line keeps headroom", () => {
    const { container } = render(
      <ProjectBudgetBars
        projects={[projectRow("p-1", "Normal", budgetOf("1000.00", "420.00"))]}
      />
    );

    expect(valueAxisLabels(container).at(-1)).toBe("120%");
  });

  it("state 19: 40 rows keep the full 28px row height inside the bounded viewport", () => {
    const projects = Array.from({ length: 40 }, (_, index) =>
      projectRow(`p-${index}`, `Project ${index}`, budgetOf("1000.00", `${index + 1}0.00`))
    );

    render(<ProjectBudgetBars projects={projects} />);

    const plotHeight = Number(
      screen.getByTestId("responsive-container").getAttribute("data-height")
    );
    expect(plotHeight).toBe(40 * 28 + 36);
    expect(screen.getByTestId("project-budget-bars")).toHaveClass("max-h-[420px]");
  });

  it("truncates long names on the axis while the CSV keeps the full name", () => {
    const longName = "Harbourside Commercial Fitout Stage Two";
    const projects = [projectRow("p-1", longName, budgetOf("1000.00", "400.00"))];

    const { container } = render(<ProjectBudgetBars projects={projects} />);

    expect(categoryAxisLabels(container)[0]).toBe("Harbourside Commercia…");
    expect(budgetBarsCsvRows(projects)[1][0]).toBe(longName);
  });

  it("state 7: with no budgeted project the card shows the no-budgets empty state", () => {
    render(<ProjectBudgetBars projects={[projectRow("p-1", "Rooftop Deck", null)]} />);

    expect(screen.getByText("No budgets set")).toBeInTheDocument();
    expect(
      screen.getByText("Set a budget on a project or trade scope to track spend against it.")
    ).toBeInTheDocument();
    expect(screen.queryByTestId("project-budget-bars")).not.toBeInTheDocument();
  });
});

describe("CompanyFinancialsDashboard budget card", () => {
  it("wires the budget card title, kpi and chart", () => {
    mockQueryState({
      data: financialsWith({
        projects: [
          projectRow("p-1", "Harbour Fitout", budgetOf("10000.00", "4200.00")),
          projectRow("p-2", "Rooftop Deck", null),
        ],
      }),
    });

    render(<CompanyFinancialsDashboard />);

    const card = screen.getByLabelText("Budget vs Actual by Project chart");
    expect(within(card).getByText("Budget vs Actual by Project")).toBeInTheDocument();
    expect(within(card).getByText("1 of 2 projects budgeted")).toBeInTheDocument();
    expect(within(card).getByTestId("project-budget-bars")).toBeInTheDocument();
  });
});

// --- Task 3: attention list and the All Projects table ---

function attentionRow(
  projectId: string,
  tier: AttentionTier,
  overrides: Partial<AttentionRow> = {}
): AttentionRow {
  return {
    projectId,
    projectName: `Project ${projectId}`,
    projectStatus: BUDGETED_STATUS,
    tier,
    anchorLabel: `Project ${projectId}`,
    spent: "11200.00",
    budgetTotal: "10000.00",
    percentUsed: "112.0",
    ...overrides,
  };
}

describe("AttentionList", () => {
  it("state 16: renders the server order unchanged, one link per row", () => {
    const rows = [
      attentionRow("c", "overrun"),
      attentionRow("a", "warning", { percentUsed: "88.0", spent: "8800.00" }),
      attentionRow("b", "incomplete", {
        spent: null,
        budgetTotal: null,
        percentUsed: null,
      }),
    ];

    render(<AttentionList rows={rows} />);

    const rendered = screen.getAllByTestId(/^attention-row-/);
    expect(rendered.map((row) => row.getAttribute("data-testid"))).toEqual([
      "attention-row-c",
      "attention-row-a",
      "attention-row-b",
    ]);
    expect(rendered[0].closest("a")).toHaveAttribute("href", "/financials/c");
  });

  it("renders one tier badge per tier with the shipped chip vocabulary", () => {
    render(
      <AttentionList
        rows={[
          attentionRow("c", "overrun"),
          attentionRow("a", "warning"),
          attentionRow("b", "incomplete"),
        ]}
      />
    );

    const overBudget = screen.getByText("Over budget");
    expect(overBudget).toHaveClass("bg-red-100");
    expect(overBudget).toHaveClass("text-red-800");
    expect(screen.getByText("Nearing budget")).toHaveClass(FINANCE_FLAG_CHIP_CLASS);
    expect(screen.getByText(INCOMPLETE_CHIP_LABEL)).toHaveClass(FINANCE_FLAG_CHIP_CLASS);
  });

  it("colours the overrun percent red, the warning percent ink, and omits it when incomplete", () => {
    render(
      <AttentionList
        rows={[
          attentionRow("c", "overrun", { percentUsed: "340.0" }),
          attentionRow("a", "warning", { percentUsed: "88.0" }),
          attentionRow("b", "incomplete", {
            spent: null,
            budgetTotal: null,
            percentUsed: null,
          }),
        ]}
      />
    );

    expect(screen.getByText("340%")).toHaveClass("text-red-800");
    expect(screen.getByText("88%")).toHaveClass("text-gray-900");
    expect(
      within(screen.getByTestId("attention-row-b")).queryByText(/%$/)
    ).not.toBeInTheDocument();
  });

  it("shows the spend sub-line on budget tiers and the incomplete caption otherwise", () => {
    render(
      <AttentionList
        rows={[
          attentionRow("c", "overrun"),
          attentionRow("b", "incomplete", {
            spent: null,
            budgetTotal: null,
            percentUsed: null,
          }),
        ]}
      />
    );

    expect(screen.getByTestId("attention-row-c")).toHaveTextContent(
      "$11200.00 of $10000.00"
    );
    expect(screen.getByTestId("attention-row-b")).toHaveTextContent(INCOMPLETE_CAPTION);
  });

  it("state 18: an inactive-status row is dimmed and carries its status badge", () => {
    render(
      <AttentionList
        rows={[attentionRow("c", "overrun", { projectStatus: "archived" })]}
      />
    );

    const row = screen.getByTestId("attention-row-c");
    expect(row).toHaveClass("opacity-60");
    expect(within(row).getByText("archived")).toBeInTheDocument();
  });

  it("state 15: an empty list renders the all-clear kpi and the empty state", () => {
    expect(attentionKpi([])).toBe("All clear");
    expect(attentionKpi([attentionRow("c", "overrun")])).toBe("1 needs attention");
    expect(
      attentionKpi([attentionRow("c", "overrun"), attentionRow("a", "warning")])
    ).toBe("2 need attention");

    render(<AttentionList rows={[]} />);

    expect(screen.getByTestId("attention-empty")).toHaveTextContent(
      "Nothing needs attention"
    );
    expect(screen.getByTestId("attention-empty")).toHaveTextContent(
      "No project is over budget, nearing its budget, or missing cost data."
    );
    expect(screen.queryByTestId("attention-list")).not.toBeInTheDocument();
  });

  it("anchors the list so the incomplete-data badge can reach it", () => {
    render(<AttentionList rows={[attentionRow("c", "overrun")]} />);

    expect(screen.getByTestId("attention-list")).toHaveAttribute("id", "attention-list");
  });
});

describe("ProjectsTable", () => {
  it("state 18: groups inactive projects below the honesty separator", () => {
    render(
      <ProjectsTable
        projects={[
          projectRow("p-1", "Archived Job", budgetOf("1000.00", "400.00"), "archived"),
          projectRow("p-2", "Running Job", budgetOf("1000.00", "300.00"), "active"),
          projectRow("p-3", "Paused Job", null, "on_hold"),
        ]}
      />
    );

    const names = Array.from(
      screen.getByTestId("projects-table").querySelectorAll("tbody tr")
    ).map((row) => row.textContent ?? "");
    expect(names[0]).toContain("Running Job");
    expect(names[1]).toContain("Paused Job");
    expect(names[2]).toContain("Inactive projects — still included in portfolio totals");
    expect(names[3]).toContain("Archived Job");
    expect(screen.getByTestId("projects-table-inactive-header")).toBeInTheDocument();
  });

  it("omits the separator when every project is active", () => {
    render(
      <ProjectsTable
        projects={[projectRow("p-2", "Running Job", budgetOf("1000.00", "300.00"))]}
      />
    );

    expect(
      screen.queryByTestId("projects-table-inactive-header")
    ).not.toBeInTheDocument();
  });

  it("sorts each group by descending cost, ties broken by name", () => {
    const grouped = groupProjectsByActivity([
      projectRow("p-1", "Beta", budgetOf("1000.00", "500.00")),
      projectRow("p-2", "Alpha", budgetOf("1000.00", "500.00")),
      projectRow("p-3", "Biggest", budgetOf("9000.00", "900.00")),
      projectRow("p-4", "Old", budgetOf("1000.00", "800.00"), "complete"),
    ]);

    expect(grouped.active.map((row) => row.name)).toEqual(["Biggest", "Alpha", "Beta"]);
    expect(grouped.inactive.map((row) => row.name)).toEqual(["Old"]);
  });

  it("renders the column headers and a per-row drill-down link", () => {
    render(
      <ProjectsTable
        projects={[projectRow("p-2", "Running Job", budgetOf("1000.00", "300.00"))]}
      />
    );

    ["Project", "Status", "Revenue", "Cost", "Margin", "Budget used"].forEach((header) => {
      expect(screen.getByText(header)).toBeInTheDocument();
    });
    const link = screen.getByLabelText("View financials for Running Job");
    expect(link).toHaveTextContent("View financials");
    expect(link).toHaveAttribute("href", "/financials/p-2");
  });

  it("state 14: a negative margin cell uses the 14px red, never the destructive token", () => {
    const project = projectRow("p-1", "Losing Job", budgetOf("1000.00", "1400.00"));
    project.margin = marginWith({ margin: "-3500.00", marginPercent: "-8.0" });

    render(<ProjectsTable projects={[project]} />);

    const cell = screen.getByTestId("projects-table-margin-p-1");
    expect(cell).toHaveTextContent("-$3500.00");
    expect(cell).toHaveClass("text-red-800");
    expect(cell).not.toHaveClass("text-destructive");
  });

  it("renders em dashes for null money, No budget without one, and the true percent", () => {
    const withoutRevenue = projectRow("p-1", "No Revenue", null);
    withoutRevenue.margin = marginWith({
      revenue: null,
      revenueBasis: "none",
      margin: null,
      marginPercent: null,
    });
    const overrun = projectRow("p-2", "Runaway", budgetOf("500.00", "1700.00"));

    render(<ProjectsTable projects={[withoutRevenue, overrun]} />);

    expect(screen.getByTestId("projects-table-revenue-p-1")).toHaveTextContent("—");
    expect(screen.getByTestId("projects-table-margin-p-1")).toHaveTextContent("—");
    expect(screen.getByTestId("projects-table-budget-used-p-1")).toHaveTextContent(
      "No budget"
    );
    expect(screen.getByTestId("projects-table-budget-used-p-2")).toHaveTextContent("340%");
  });

  it("state 6: with no projects at all the table shows its empty state", () => {
    render(<ProjectsTable projects={[]} />);

    expect(screen.getByText("No projects yet")).toBeInTheDocument();
    expect(
      screen.getByText("Create a project to start tracking margin and budget.")
    ).toBeInTheDocument();
    expect(screen.queryByTestId("projects-table")).not.toBeInTheDocument();
  });
});

describe("CompanyFinancialsDashboard attention and table cards", () => {
  it("wires the attention card and the All Projects card", () => {
    mockQueryState({
      data: financialsWith({
        projects: [projectRow("p-1", "Harbour Fitout", budgetOf("10000.00", "11200.00"))],
        attention: [attentionRow("p-1", "overrun")],
      }),
    });

    render(<CompanyFinancialsDashboard />);

    const card = screen.getByLabelText("Needs Attention list");
    expect(within(card).getByText("Needs Attention")).toBeInTheDocument();
    expect(within(card).getByText("1 needs attention")).toBeInTheDocument();
    expect(within(card).getByTestId("attention-list")).toBeInTheDocument();
    expect(screen.getByText("All Projects")).toBeInTheDocument();
    expect(screen.getByTestId("projects-table")).toBeInTheDocument();
  });
});
