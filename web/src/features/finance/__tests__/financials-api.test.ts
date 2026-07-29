import { apiGet } from "@/lib/api-client";
import {
  fetchCompanyFinancials,
  fetchProjectFinancials,
  fetchProjectMarginTrend,
} from "../api";

jest.mock("@/lib/api-client", () => ({
  apiGet: jest.fn(),
  apiPost: jest.fn(),
  apiPatch: jest.fn(),
  apiDelete: jest.fn(),
  apiUpload: jest.fn(),
  ApiError: class ApiError extends Error {},
}));

const mockApiGet = apiGet as jest.MockedFunction<typeof apiGet>;

const PROJECT_ID = "11111111-1111-1111-1111-111111111111";

function marginSummaryPayload(overrides: Record<string, unknown> = {}) {
  return {
    revenue: "182400.00",
    revenue_basis: "mixed",
    margin: "61100.00",
    margin_percent: "33.5",
    incomplete: false,
    incomplete_reasons: [],
    ...overrides,
  };
}

function companyPayload(overrides: Record<string, unknown> = {}) {
  return {
    portfolio: {
      cost: "121300.00",
      quoted_revenue: "18400.00",
      incomplete_project_count: 0,
      margin: marginSummaryPayload(),
    },
    projects: [],
    attention: [],
    ...overrides,
  };
}

describe("fetchCompanyFinancials", () => {
  beforeEach(() => mockApiGet.mockReset());

  test("keeps a null portfolio revenue null instead of coercing it to zero", async () => {
    mockApiGet.mockResolvedValue(
      companyPayload({
        portfolio: {
          cost: "121300.00",
          quoted_revenue: null,
          incomplete_project_count: 2,
          margin: marginSummaryPayload({
            revenue: null,
            revenue_basis: "none",
            margin: null,
            margin_percent: null,
            incomplete: true,
            incomplete_reasons: ["unrated_labor"],
          }),
        },
      })
    );

    const result = await fetchCompanyFinancials();

    expect(result.portfolio.quotedRevenue).toBeNull();
    expect(result.portfolio.margin.revenue).toBeNull();
    expect(result.portfolio.margin.margin).toBeNull();
    expect(result.portfolio.margin.marginPercent).toBeNull();
    expect(result.portfolio.margin.incompleteReasons).toEqual(["unrated_labor"]);
    expect(result.portfolio.incompleteProjectCount).toBe(2);
  });

  test("maps a project row with no budget block to budget: null", async () => {
    mockApiGet.mockResolvedValue(
      companyPayload({
        projects: [
          {
            project_id: PROJECT_ID,
            name: "Downtown Remodel",
            status: "active",
            cost: "40120.00",
            margin: marginSummaryPayload(),
          },
          {
            project_id: "22222222-2222-2222-2222-222222222222",
            name: "Lakeside Build",
            status: "draft",
            cost: "0.00",
            margin: marginSummaryPayload(),
            budget: {
              budget_id: "b-1",
              total: "10000.00",
              spent: "11200.00",
              remaining: "-1200.00",
              percent_used: "112.0",
            },
          },
        ],
      })
    );

    const result = await fetchCompanyFinancials();

    expect(result.projects[0]).toMatchObject({
      projectId: PROJECT_ID,
      name: "Downtown Remodel",
      status: "active",
      cost: "40120.00",
      budget: null,
    });
    expect(result.projects[1].budget).toEqual({
      budgetId: "b-1",
      total: "10000.00",
      spent: "11200.00",
      remaining: "-1200.00",
      percentUsed: "112.0",
    });
  });

  test("maps attention rows and keeps their null money fields null", async () => {
    mockApiGet.mockResolvedValue(
      companyPayload({
        attention: [
          {
            project_id: PROJECT_ID,
            project_name: "Downtown Remodel",
            project_status: "active",
            tier: "overrun",
            anchor_label: "Downtown Remodel — Plumbing scope",
            spent: "11200.00",
            budget_total: "10000.00",
            percent_used: "112.0",
          },
          {
            project_id: "33333333-3333-3333-3333-333333333333",
            project_name: "Harbor Fitout",
            project_status: "complete",
            tier: "incomplete",
            anchor_label: "Harbor Fitout",
            spent: null,
            budget_total: null,
            percent_used: null,
          },
        ],
      })
    );

    const result = await fetchCompanyFinancials();

    expect(result.attention[0]).toEqual({
      projectId: PROJECT_ID,
      projectName: "Downtown Remodel",
      projectStatus: "active",
      tier: "overrun",
      anchorLabel: "Downtown Remodel — Plumbing scope",
      spent: "11200.00",
      budgetTotal: "10000.00",
      percentUsed: "112.0",
    });
    expect(result.attention[1]).toMatchObject({
      tier: "incomplete",
      spent: null,
      budgetTotal: null,
      percentUsed: null,
    });
  });

  test("throws when the portfolio margin block is missing", async () => {
    mockApiGet.mockResolvedValue(
      companyPayload({
        portfolio: {
          cost: "121300.00",
          quoted_revenue: null,
          incomplete_project_count: 0,
        },
      })
    );

    await expect(fetchCompanyFinancials()).rejects.toThrow(/margin/i);
  });
});

describe("fetchProjectFinancials", () => {
  beforeEach(() => mockApiGet.mockReset());

  test("maps the breakdown through the shipped cost-breakdown mapper and maps scopes", async () => {
    mockApiGet.mockResolvedValue({
      project_id: PROJECT_ID,
      name: "Downtown Remodel",
      status: "active",
      breakdown: {
        categories: [
          { category_id: "cat-1", category_name: "Materials", total: "12000.00" },
        ],
        labor: {
          total: "28120.00",
          rated_seconds: 7200,
          unrated_seconds: 1800,
          basis: "unburdened",
        },
        labor_tracked_at_job_level: true,
        grand_total: "40120.00",
        margin: marginSummaryPayload(),
        budget: null,
      },
      scopes: [
        {
          trade_scope_id: "scope-1",
          trade_name: "Plumbing",
          spent: "8200.00",
          budget: {
            budget_id: "b-2",
            total: "9000.00",
            spent: "8200.00",
            remaining: "800.00",
            percent_used: "91.1",
          },
        },
        { trade_scope_id: "scope-2", trade_name: "Electrical", spent: "0.00", budget: null },
      ],
    });

    const result = await fetchProjectFinancials(PROJECT_ID);

    expect(mockApiGet).toHaveBeenCalledWith(
      `/api/v1/projects/${PROJECT_ID}/financials`
    );
    expect(result.breakdown.categories).toEqual([
      { categoryId: "cat-1", categoryName: "Materials", total: "12000.00" },
    ]);
    expect(result.breakdown.labor).toEqual({
      total: "28120.00",
      ratedSeconds: 7200,
      unratedSeconds: 1800,
      basis: "unburdened",
    });
    expect(result.breakdown.laborTrackedAtJobLevel).toBe(true);
    expect(result.breakdown.grandTotal).toBe("40120.00");
    expect(result.breakdown.budget).toBeNull();
    expect(result.scopes[0]).toEqual({
      tradeScopeId: "scope-1",
      tradeName: "Plumbing",
      spent: "8200.00",
      budget: {
        budgetId: "b-2",
        total: "9000.00",
        spent: "8200.00",
        remaining: "800.00",
        percentUsed: "91.1",
      },
    });
    expect(result.scopes[1].budget).toBeNull();
  });
});

describe("fetchProjectMarginTrend", () => {
  beforeEach(() => mockApiGet.mockReset());

  test("requests the trend window as a query param", async () => {
    mockApiGet.mockResolvedValue({
      project_id: PROJECT_ID,
      window: "3m",
      buckets: [],
    });

    await fetchProjectMarginTrend(PROJECT_ID, "3m");

    const requestedPath = mockApiGet.mock.calls[0][0];
    expect(requestedPath).toMatch(/\/financials\/trend\?window=3m$/);
  });

  test("preserves bucket order and keeps a null bucket margin null", async () => {
    mockApiGet.mockResolvedValue({
      project_id: PROJECT_ID,
      window: "12m",
      buckets: [
        { month: "2026-01", cost: "12000.00", margin: marginSummaryPayload() },
        {
          month: "2026-02",
          cost: "9000.00",
          margin: marginSummaryPayload({
            revenue: null,
            revenue_basis: "none",
            margin: null,
            margin_percent: null,
          }),
        },
        { month: "2026-03", cost: "15000.00", margin: marginSummaryPayload() },
      ],
    });

    const result = await fetchProjectMarginTrend(PROJECT_ID, "12m");

    expect(result.projectId).toBe(PROJECT_ID);
    expect(result.window).toBe("12m");
    expect(result.buckets.map((bucket) => bucket.month)).toEqual([
      "2026-01",
      "2026-02",
      "2026-03",
    ]);
    expect(result.buckets[1].margin.margin).toBeNull();
    expect(result.buckets[1].margin.revenue).toBeNull();
    expect(result.buckets[1].cost).toBe("9000.00");
  });
});
