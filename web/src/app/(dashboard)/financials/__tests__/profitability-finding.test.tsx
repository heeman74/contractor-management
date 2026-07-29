import React from "react";
import { render, screen, within } from "@testing-library/react";

import ProjectFinancialsDashboard from "../[projectId]/_components/project-financials-dashboard";
import {
  ProfitabilityFindingCard,
  emptyStateCopy,
  findingDateLine,
  revenueBasisCaption,
} from "../[projectId]/_components/profitability-finding-card";
import { QUOTED_BASIS_CAPTION } from "../_components/finance-summary-tiles";
import {
  UNBURDENED_BODY,
  UNBURDENED_TITLE,
} from "@/features/finance/components/CostBreakdownSummary";
import {
  useProjectFinancials,
  useProjectMarginTrend,
  useProjectProfitabilityFinding,
} from "@/features/finance/hooks";
import type {
  CostBreakdown,
  MarginSummary,
  MarginTrend,
  ProfitabilityFinding,
  ProjectFinancials,
  ScopeBudgetRow,
} from "@/features/finance/types";

jest.mock("@/features/finance/hooks", () => ({
  useProjectFinancials: jest.fn(),
  useProjectMarginTrend: jest.fn(),
  useProjectProfitabilityFinding: jest.fn(),
}));
jest.mock("sonner", () => ({ toast: { error: jest.fn(), success: jest.fn() } }));
jest.mock("next/navigation", () => ({ useRouter: () => ({ push: jest.fn() }) }));

/** Recharts measures the DOM, which jsdom cannot do — the shipped drill-down
 *  test's fixed-size stand-in, reused so the chart cards render here too. */
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
        {React.cloneElement(children, { width: 800, height } as Record<string, unknown>)}
      </div>
    ),
  };
});

const PROJECT_ID = "p-1";
const NARRATIVE_BOUND = 600;
const ELLIPSIS = "…";

const DISCLOSURE =
  "AI-written from this project's recorded figures — every number is from your data, never an AI estimate.";
const MIXED_BASIS_CAPTION = "Includes revenue from approved quotes — not yet invoiced.";
const ERROR_MESSAGE = "Couldn't load the profitability finding. Refresh to try again.";

const OPEN_FINDING: ProfitabilityFinding = {
  id: "f-1",
  projectId: PROJECT_ID,
  severity: "warning",
  narrative:
    "Margin on this project has slipped from 22% to 14% since the electrical rework was logged.",
  correctiveAction: "Review the electrical rework hours before issuing the next invoice.",
  revenueBasis: "invoiced",
  laborIncluded: false,
  foundOn: "2026-07-29",
  lastConfirmedOn: "2026-07-29",
};

function findingWith(overrides: Partial<ProfitabilityFinding> = {}): ProfitabilityFinding {
  return { ...OPEN_FINDING, ...overrides };
}

function renderCard(
  props: Partial<React.ComponentProps<typeof ProfitabilityFindingCard>> = {}
) {
  return render(
    <ProfitabilityFindingCard
      finding={OPEN_FINDING}
      isLoading={false}
      isError={false}
      incompleteCostData={false}
      {...props}
    />
  );
}

// --- The card: states 3-16 and 21 ---

describe("ProfitabilityFindingCard", () => {
  it("state 3: a loading finding renders the skeleton bars and no narrative", () => {
    renderCard({ finding: null, isLoading: true });

    expect(screen.getByTestId("profitability-finding-skeleton")).toBeInTheDocument();
    expect(screen.getByText("Profitability Finding")).toBeInTheDocument();
    expect(
      screen.queryByTestId("profitability-finding-narrative")
    ).not.toBeInTheDocument();
    expect(screen.queryByTestId("profitability-finding-empty")).not.toBeInTheDocument();
  });

  it("state 4: the warning band renders the amber chip", () => {
    renderCard({ finding: findingWith({ severity: "warning" }) });

    const chip = screen.getByTestId("profitability-finding-severity");
    expect(chip).toHaveTextContent("Margin warning");
    expect(chip).toHaveClass("bg-brand/15");
    expect(chip).toHaveClass("text-amber-900");
  });

  it("state 5: the critical band changes the chip and nothing else about the chrome", () => {
    renderCard({ finding: findingWith({ severity: "critical" }) });

    const chip = screen.getByTestId("profitability-finding-severity");
    expect(chip).toHaveTextContent("Margin critical");
    expect(chip).toHaveClass("bg-red-100");
    expect(chip).toHaveClass("text-red-800");

    const card = screen.getByTestId("profitability-finding");
    expect(card.className).not.toMatch(/border-red/);
    expect(card.className).not.toMatch(/bg-red/);
  });

  it("state 6: narrative and action render verbatim under the SUGGESTED ACTION eyebrow", () => {
    const finding = findingWith();
    renderCard({ finding });

    // AI-authored prose is asserted through the prop, never as a literal sentence.
    expect(screen.getByTestId("profitability-finding-narrative")).toHaveTextContent(
      finding.narrative
    );
    expect(screen.getByTestId("profitability-finding-action")).toHaveTextContent(
      finding.correctiveAction
    );
    expect(screen.getByText("SUGGESTED ACTION")).toHaveClass("font-semibold");
    expect(screen.getByText("SUGGESTED ACTION")).toHaveClass("text-gray-700");
  });

  it("state 7: a first-night finding names only the found date", () => {
    renderCard({ finding: findingWith({ foundOn: "2026-07-29", lastConfirmedOn: "2026-07-29" }) });

    expect(screen.getByTestId("profitability-finding-date")).toHaveTextContent(
      "Found Jul 29, 2026"
    );
    expect(screen.getByTestId("profitability-finding-date")).not.toHaveTextContent(
      "Last confirmed"
    );
  });

  it("state 8: a re-confirmed finding names both dates, never just the newer one", () => {
    renderCard({ finding: findingWith({ foundOn: "2026-07-22", lastConfirmedOn: "2026-07-29" }) });

    expect(screen.getByTestId("profitability-finding-date")).toHaveTextContent(
      "Found Jul 22, 2026 · Last confirmed Jul 29, 2026"
    );
    expect(findingDateLine(findingWith({ foundOn: "2026-07-22", lastConfirmedOn: "2026-07-29" })))
      .toBe("Found Jul 22, 2026 · Last confirmed Jul 29, 2026");
  });

  it("state 9: a quoted basis renders the shipped quoted caption", () => {
    renderCard({ finding: findingWith({ revenueBasis: "quoted" }) });

    expect(screen.getByTestId("profitability-finding-basis-note")).toHaveTextContent(
      QUOTED_BASIS_CAPTION
    );
    expect(revenueBasisCaption("quoted")).toBe(QUOTED_BASIS_CAPTION);
  });

  it("state 10: a mixed basis renders the amount-free sibling and fabricates no figure", () => {
    renderCard({ finding: findingWith({ revenueBasis: "mixed" }) });

    const note = screen.getByTestId("profitability-finding-basis-note");
    expect(note).toHaveTextContent(MIXED_BASIS_CAPTION);
    expect(note.textContent).not.toMatch(/\$/);
    expect(revenueBasisCaption("mixed")).toBe(MIXED_BASIS_CAPTION);
  });

  it("state 11: an invoiced basis has nothing to qualify, so no caption renders", () => {
    renderCard({ finding: findingWith({ revenueBasis: "invoiced" }) });

    expect(
      screen.queryByTestId("profitability-finding-basis-note")
    ).not.toBeInTheDocument();
    expect(revenueBasisCaption("invoiced")).toBeNull();
    expect(revenueBasisCaption("none")).toBeNull();
  });

  it("state 12: labor in the analysis renders the composed unburdened caveat", () => {
    renderCard({ finding: findingWith({ laborIncluded: true }) });

    expect(screen.getByTestId("profitability-finding-labor-note")).toHaveTextContent(
      `${UNBURDENED_TITLE}: ${UNBURDENED_BODY}`
    );
  });

  it("state 13: no labor in the analysis renders no labor caveat", () => {
    renderCard({ finding: findingWith({ laborIncluded: false }) });

    expect(
      screen.queryByTestId("profitability-finding-labor-note")
    ).not.toBeInTheDocument();
  });

  it("state 14: the disclosure renders for every finding and is always last", () => {
    renderCard({
      finding: findingWith({ revenueBasis: "quoted", laborIncluded: true }),
    });

    const disclosure = screen.getByTestId("profitability-finding-disclosure");
    expect(disclosure).toHaveTextContent(DISCLOSURE);
    expect(disclosure.parentElement?.lastElementChild).toBe(disclosure);
    expect(disclosure.parentElement?.children).toHaveLength(3);
  });

  it("state 15: no finding with complete data reads as nothing flagged, not as silence", () => {
    renderCard({ finding: null });

    const empty = screen.getByTestId("profitability-finding-empty");
    expect(empty).toHaveTextContent("No margin erosion flagged");
    expect(empty).toHaveTextContent(
      "A nightly AI review posts a finding here when this project's margin starts to slip."
    );
    expect(screen.queryByTestId("profitability-finding-severity")).not.toBeInTheDocument();
  });

  it("state 16: no finding with incomplete data says why the AI was silent", () => {
    renderCard({ finding: null, incompleteCostData: true });

    const empty = screen.getByTestId("profitability-finding-empty");
    expect(empty).toHaveTextContent("Not analyzed — incomplete cost data");
    expect(empty).toHaveTextContent(
      "AI skips projects with missing or unrated costs, so a finding can never rest on understated numbers."
    );
    expect(empty).not.toHaveTextContent("No margin erosion flagged");
    expect(emptyStateCopy(true).heading).toBe("Not analyzed — incomplete cost data");
    expect(emptyStateCopy(false).heading).toBe("No margin erosion flagged");
  });

  it("state 19: an errored query renders the in-card error line and no finding body", () => {
    renderCard({ finding: null, isError: true });

    expect(screen.getByTestId("profitability-finding-error")).toHaveTextContent(
      ERROR_MESSAGE
    );
    expect(screen.getByTestId("profitability-finding-error")).toHaveClass("text-red-800");
    expect(screen.queryByTestId("profitability-finding-empty")).not.toBeInTheDocument();
    expect(
      screen.queryByTestId("profitability-finding-disclosure")
    ).not.toBeInTheDocument();
  });

  it("state 21: a narrative at the 600-character bound renders in full, unclamped", () => {
    const longNarrative = "x".repeat(NARRATIVE_BOUND);
    renderCard({ finding: findingWith({ narrative: longNarrative }) });

    const node = screen.getByTestId("profitability-finding-narrative");
    expect(node.textContent).toHaveLength(NARRATIVE_BOUND);
    expect(node.textContent).not.toContain(ELLIPSIS);
    expect(node.className).not.toMatch(/line-clamp|truncate|overflow-hidden/);
  });

  it("contains nothing to tab to: no button, no link, no dismiss control", () => {
    renderCard();

    expect(screen.queryAllByRole("button")).toHaveLength(0);
    expect(screen.queryAllByRole("link")).toHaveLength(0);
  });
});

// --- The keystone: a findings outage must never blank the money dashboard ---

const HEALTHY_MARGIN: MarginSummary = {
  revenue: "100000.00",
  revenueBasis: "invoiced",
  margin: "21000.00",
  marginPercent: "21.0",
  incomplete: false,
  incompleteReasons: [],
};

const HEALTHY_BREAKDOWN: CostBreakdown = {
  categories: [{ categoryId: "c-1", categoryName: "Materials", total: "30000.00" }],
  labor: { total: "49000.00", ratedSeconds: 3600, unratedSeconds: 0, basis: "unburdened" },
  laborTrackedAtJobLevel: true,
  grandTotal: "79000.00",
  margin: HEALTHY_MARGIN,
  budget: null,
};

const BUDGETED_SCOPE: ScopeBudgetRow = {
  tradeScopeId: "s-1",
  tradeName: "Electrical",
  spent: "8500.00",
  budget: {
    budgetId: "b-1",
    total: "10000.00",
    spent: "8500.00",
    remaining: "1500.00",
    percentUsed: "85.0",
  },
};

const HEALTHY_PROJECT: ProjectFinancials = {
  projectId: PROJECT_ID,
  name: "Harbour Fitout",
  status: "active",
  breakdown: HEALTHY_BREAKDOWN,
  scopes: [BUDGETED_SCOPE],
};

const HEALTHY_TREND: MarginTrend = {
  projectId: PROJECT_ID,
  window: "12m",
  buckets: [{ month: "2026-01", cost: "10000.00", margin: HEALTHY_MARGIN }],
};

const mockUseProjectFinancials = useProjectFinancials as jest.Mock;
const mockUseProjectMarginTrend = useProjectMarginTrend as jest.Mock;
const mockUseProjectProfitabilityFinding = useProjectProfitabilityFinding as jest.Mock;

function mockHealthyPageWithFinding(finding: Record<string, unknown>) {
  mockUseProjectFinancials.mockReturnValue({
    data: HEALTHY_PROJECT,
    isLoading: false,
    isError: false,
    error: null,
  });
  mockUseProjectMarginTrend.mockReturnValue({
    data: HEALTHY_TREND,
    isLoading: false,
    isFetching: false,
  });
  mockUseProjectProfitabilityFinding.mockReturnValue(finding);
}

function expectMoneyDashboardIntact() {
  expect(screen.getByTestId("project-revenue")).toHaveTextContent("$100000.00");
  expect(screen.getByTestId("project-cost")).toHaveTextContent("$79000.00");
  expect(screen.getByTestId("project-margin")).toHaveTextContent("$21000.00");
  expect(screen.getByTestId("margin-trend-chart")).toBeInTheDocument();
  expect(screen.getByTestId("scope-budget-bars")).toBeInTheDocument();
  expect(screen.getByTestId("category-mix-chart")).toBeInTheDocument();
  expect(screen.queryByTestId("financials-skeleton")).not.toBeInTheDocument();
}

describe("ProjectFinancialsDashboard — finding failure surface", () => {
  beforeEach(() => {
    mockUseProjectFinancials.mockReset();
    mockUseProjectMarginTrend.mockReset();
    mockUseProjectProfitabilityFinding.mockReset();
  });

  /**
   * KEYSTONE (state 19). The finding query owns its own key and its own failure
   * surface: it is excluded from the page loading gate precisely so a findings
   * outage renders one in-card line while every audited figure beside it still
   * renders. If this test ever fails, the money dashboard has been made to
   * depend on the AI.
   */
  it("state 19: a failed finding query errors in-card while the whole dashboard renders", () => {
    mockHealthyPageWithFinding({ data: undefined, isLoading: false, isError: true });

    render(<ProjectFinancialsDashboard projectId={PROJECT_ID} />);

    expect(screen.getByTestId("profitability-finding-error")).toHaveTextContent(
      ERROR_MESSAGE
    );
    expectMoneyDashboardIntact();
  });

  it("state 3: a finding still in flight never delays the money dashboard", () => {
    mockHealthyPageWithFinding({ data: undefined, isLoading: true, isError: false });

    render(<ProjectFinancialsDashboard projectId={PROJECT_ID} />);

    expect(screen.getByTestId("profitability-finding-skeleton")).toBeInTheDocument();
    expectMoneyDashboardIntact();
  });

  it("mounts the card between the summary tiles and the Margin Trend chart", () => {
    mockHealthyPageWithFinding({
      data: findingWith({ severity: "critical" }),
      isLoading: false,
      isError: false,
    });

    const { container } = render(<ProjectFinancialsDashboard projectId={PROJECT_ID} />);

    const card = screen.getByTestId("profitability-finding");
    expect(within(card).getByTestId("profitability-finding-severity")).toHaveTextContent(
      "Margin critical"
    );

    const sections = Array.from(container.firstElementChild?.children ?? []);
    const tilesIndex = sections.findIndex((node) =>
      node.contains(screen.getByTestId("project-revenue"))
    );
    const cardIndex = sections.indexOf(card);
    const trendIndex = sections.findIndex((node) =>
      node.contains(screen.getByTestId("margin-trend-chart"))
    );
    expect(cardIndex).toBeGreaterThan(tilesIndex);
    expect(cardIndex).toBeLessThan(trendIndex);
  });

  it("passes the project's own incomplete flag through to the honesty empty state", () => {
    mockUseProjectFinancials.mockReturnValue({
      data: {
        ...HEALTHY_PROJECT,
        breakdown: {
          ...HEALTHY_BREAKDOWN,
          margin: { ...HEALTHY_MARGIN, incomplete: true, incompleteReasons: ["unrated_hours"] },
        },
      },
      isLoading: false,
      isError: false,
      error: null,
    });
    mockUseProjectMarginTrend.mockReturnValue({
      data: HEALTHY_TREND,
      isLoading: false,
      isFetching: false,
    });
    mockUseProjectProfitabilityFinding.mockReturnValue({
      data: undefined,
      isLoading: false,
      isError: false,
    });

    render(<ProjectFinancialsDashboard projectId={PROJECT_ID} />);

    expect(screen.getByTestId("profitability-finding-empty")).toHaveTextContent(
      "Not analyzed — incomplete cost data"
    );
  });
});
