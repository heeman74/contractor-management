import React from "react";
import { render, screen } from "@testing-library/react";
import { toast } from "sonner";

import CompanyFinancialsDashboard from "../_components/company-financials-dashboard";
import { FinanceSummaryTiles } from "../_components/finance-summary-tiles";
import { useCompanyFinancials } from "@/features/finance/hooks";
import { INCOMPLETE_CAPTION } from "@/features/finance/components/MarginSummarySection";
import type {
  CompanyFinancials,
  MarginSummary,
  PortfolioTotals,
} from "@/features/finance/types";

jest.mock("@/features/finance/hooks", () => ({ useCompanyFinancials: jest.fn() }));
jest.mock("sonner", () => ({ toast: { error: jest.fn(), success: jest.fn() } }));

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
