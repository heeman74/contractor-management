import React from "react";
import { render, screen, within } from "@testing-library/react";

import ProjectFinancialsDashboard from "../[projectId]/_components/project-financials-dashboard";
import { useProjectFinancials, useProjectMarginTrend } from "@/features/finance/hooks";
import { ApiError } from "@/lib/api-client";
import type {
  CostBreakdown,
  MarginSummary,
  MarginTrend,
  ProjectFinancials,
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
