import { test, expect, type Page, type Route } from "@playwright/test";

// E2E: company financial overview + project drill-down + the finance.view gate
// (MARG-04, SC1-SC3, 35-UI-SPEC states 1-34). Follows the phase-33/34 recipe —
// mock /api/proxy, log in through the UI so Redux auth + permissions populate,
// then SPA-navigate via the sidebar.

const FINANCE_PERMISSIONS = ["projects.view", "finance.view"];
const NON_FINANCE_PERMISSIONS = ["projects.view", "jobs.view"];

const OVERRUN_PROJECT_ID = "proj-f-1";
const WARNING_PROJECT_ID = "proj-f-2";
const UNBUDGETED_PROJECT_ID = "proj-f-3";
const ARCHIVED_PROJECT_ID = "proj-f-4";

const OVERRUN_PROJECT_NAME = "Downtown Remodel";
const WARNING_PROJECT_NAME = "Harbor Lofts";
const UNBUDGETED_PROJECT_NAME = "Cedar Duplex";
const ARCHIVED_PROJECT_NAME = "Old Mill Retrofit";

interface MarginFixture {
  revenue: string | null;
  revenue_basis: string;
  margin: string | null;
  margin_percent: string | null;
  incomplete: boolean;
  incomplete_reasons: string[];
}

/** A margin block with nothing in it — a null is honest absence, never a zero. */
const ABSENT_MARGIN: MarginFixture = {
  revenue: null,
  revenue_basis: "none",
  margin: null,
  margin_percent: null,
  incomplete: false,
  incomplete_reasons: [],
};

function marginFixture(overrides: Partial<MarginFixture>): MarginFixture {
  return { ...ABSENT_MARGIN, ...overrides };
}

interface BudgetFixture {
  budget_id: string;
  total: string;
  spent: string;
  remaining: string;
  percent_used: string;
}

/** 340% — past the 200% axis clamp, so its bar carries the overflow label. */
const OVERRUN_BUDGET: BudgetFixture = {
  budget_id: "budget-f-1",
  total: "10000.00",
  spent: "34000.00",
  remaining: "-24000.00",
  percent_used: "340.0",
};
const WARNING_BUDGET: BudgetFixture = {
  budget_id: "budget-f-2",
  total: "10000.00",
  spent: "8200.00",
  remaining: "1800.00",
  percent_used: "82.0",
};
const HEALTHY_BUDGET: BudgetFixture = {
  budget_id: "budget-f-4",
  total: "5000.00",
  spent: "2000.00",
  remaining: "3000.00",
  percent_used: "40.0",
};

/** Four projects, one per rendering branch: the clamp case, the warning band, a
 *  project with no budget at all, and an inactive one that still counts. */
const PORTFOLIO_PROJECTS = [
  {
    project_id: OVERRUN_PROJECT_ID,
    name: OVERRUN_PROJECT_NAME,
    status: "active",
    cost: "40120.00",
    margin: marginFixture({
      revenue: "52000.00",
      revenue_basis: "mixed",
      margin: "11880.00",
      margin_percent: "22.8",
    }),
    budget: OVERRUN_BUDGET,
  },
  {
    project_id: WARNING_PROJECT_ID,
    name: WARNING_PROJECT_NAME,
    status: "active",
    cost: "8200.00",
    margin: marginFixture({
      revenue: "12000.00",
      revenue_basis: "invoiced",
      margin: "3800.00",
      margin_percent: "31.7",
    }),
    budget: WARNING_BUDGET,
  },
  {
    project_id: UNBUDGETED_PROJECT_ID,
    name: UNBUDGETED_PROJECT_NAME,
    status: "active",
    cost: "5100.00",
    margin: marginFixture({
      revenue: "4000.00",
      revenue_basis: "quoted",
      margin: "-1100.00",
      margin_percent: "-27.5",
      incomplete: true,
      incomplete_reasons: ["unrated_labor"],
    }),
    budget: null,
  },
  {
    project_id: ARCHIVED_PROJECT_ID,
    name: ARCHIVED_PROJECT_NAME,
    status: "archived",
    cost: "2000.00",
    margin: marginFixture({ incomplete: true, incomplete_reasons: ["no_cost_data"] }),
    budget: HEALTHY_BUDGET,
  },
];

/** Server-ordered by D-08 tier: overrun, then warning, then incomplete. The two
 *  incomplete rows are exactly the portfolio's incomplete_project_count. */
const ATTENTION_ROWS = [
  {
    project_id: OVERRUN_PROJECT_ID,
    project_name: OVERRUN_PROJECT_NAME,
    project_status: "active",
    tier: "overrun",
    anchor_label: `${OVERRUN_PROJECT_NAME} — Plumbing scope`,
    spent: OVERRUN_BUDGET.spent,
    budget_total: OVERRUN_BUDGET.total,
    percent_used: OVERRUN_BUDGET.percent_used,
  },
  {
    project_id: WARNING_PROJECT_ID,
    project_name: WARNING_PROJECT_NAME,
    project_status: "active",
    tier: "warning",
    anchor_label: WARNING_PROJECT_NAME,
    spent: WARNING_BUDGET.spent,
    budget_total: WARNING_BUDGET.total,
    percent_used: WARNING_BUDGET.percent_used,
  },
  {
    project_id: UNBUDGETED_PROJECT_ID,
    project_name: UNBUDGETED_PROJECT_NAME,
    project_status: "active",
    tier: "incomplete",
    anchor_label: UNBUDGETED_PROJECT_NAME,
    spent: null,
    budget_total: null,
    percent_used: null,
  },
  {
    project_id: ARCHIVED_PROJECT_ID,
    project_name: ARCHIVED_PROJECT_NAME,
    project_status: "archived",
    tier: "incomplete",
    anchor_label: ARCHIVED_PROJECT_NAME,
    spent: null,
    budget_total: null,
    percent_used: null,
  },
];

const INCOMPLETE_PROJECT_COUNT = 2;
const PORTFOLIO_QUOTED_REVENUE = "18400.00";

const COMPANY_FINANCIALS = {
  portfolio: {
    cost: "55420.00",
    quoted_revenue: PORTFOLIO_QUOTED_REVENUE,
    incomplete_project_count: INCOMPLETE_PROJECT_COUNT,
    margin: marginFixture({
      revenue: "68000.00",
      revenue_basis: "mixed",
      margin: "12580.00",
      margin_percent: "18.5",
      incomplete: true,
      incomplete_reasons: ["unrated_labor"],
    }),
  },
  projects: PORTFOLIO_PROJECTS,
  attention: ATTENTION_ROWS,
};

const BUDGETED_SCOPE_ID = "scope-f-1";
const UNBUDGETED_SCOPE_ID = "scope-f-2";
const EMPTY_SCOPE_ID = "scope-f-3";

/** Labor plus four categories, a project budget, and three scopes: budgeted,
 *  unbudgeted, and one with nothing spent on it yet. */
const PROJECT_FINANCIALS = {
  project_id: OVERRUN_PROJECT_ID,
  name: OVERRUN_PROJECT_NAME,
  status: "active",
  breakdown: {
    categories: [
      { category_id: "cat-materials", category_name: "Materials", total: "18000.00" },
      { category_id: "cat-sub", category_name: "Subcontractor", total: "9000.00" },
      { category_id: "cat-other", category_name: "Other", total: "3000.00" },
      { category_id: "cat-permits", category_name: "Permits", total: "1200.00" },
    ],
    labor: {
      total: "8920.00",
      rated_seconds: 288000,
      unrated_seconds: 3600,
      basis: "unburdened",
    },
    labor_tracked_at_job_level: false,
    grand_total: "40120.00",
    margin: marginFixture({
      revenue: "52000.00",
      revenue_basis: "mixed",
      margin: "11880.00",
      margin_percent: "22.8",
    }),
    budget: OVERRUN_BUDGET,
  },
  scopes: [
    {
      trade_scope_id: BUDGETED_SCOPE_ID,
      trade_name: "Plumbing",
      spent: WARNING_BUDGET.spent,
      budget: WARNING_BUDGET,
    },
    {
      trade_scope_id: UNBUDGETED_SCOPE_ID,
      trade_name: "Electrical",
      spent: "5000.00",
      budget: null,
    },
    {
      trade_scope_id: EMPTY_SCOPE_ID,
      trade_name: "Framing",
      spent: "0.00",
      budget: null,
    },
  ],
};

/** Dense monthly buckets. The first carries a null margin on a "none" basis so
 *  the line renders a real gap rather than a fabricated break-even month. */
const TREND_BUCKETS = [
  { month: "2026-02", cost: "6000.00", margin: marginFixture({}) },
  {
    month: "2026-03",
    cost: "12000.00",
    margin: marginFixture({
      revenue: "18000.00",
      revenue_basis: "invoiced",
      margin: "6000.00",
      margin_percent: "33.3",
    }),
  },
  {
    month: "2026-04",
    cost: "19000.00",
    margin: marginFixture({
      revenue: "26000.00",
      revenue_basis: "invoiced",
      margin: "7000.00",
      margin_percent: "26.9",
    }),
  },
  {
    month: "2026-05",
    cost: "26000.00",
    margin: marginFixture({
      revenue: "34000.00",
      revenue_basis: "invoiced",
      margin: "8000.00",
      margin_percent: "23.5",
    }),
  },
  {
    month: "2026-06",
    cost: "33000.00",
    margin: marginFixture({
      revenue: "43000.00",
      revenue_basis: "mixed",
      margin: "10000.00",
      margin_percent: "23.3",
    }),
  },
  {
    month: "2026-07",
    cost: "40120.00",
    margin: marginFixture({
      revenue: "52000.00",
      revenue_basis: "mixed",
      margin: "11880.00",
      margin_percent: "22.8",
    }),
  },
];

const SHORT_WINDOW_MONTHS = 3;

const MARGIN_TREND_12M = {
  project_id: OVERRUN_PROJECT_ID,
  window: "12m",
  buckets: TREND_BUCKETS,
};

/** The same bucket objects, not copies: a month shared by two windows must carry
 *  byte-identical values, because the window slices buckets and never records. */
const MARGIN_TREND_3M = {
  project_id: OVERRUN_PROJECT_ID,
  window: "3m",
  buckets: TREND_BUCKETS.slice(-SHORT_WINDOW_MONTHS),
};

const PROXY_GLOB = "**/api/proxy**";
const FINANCIALS_PATH_MARKER = "/financials";
const TREND_PATH_MARKER = "/financials/trend";
const COMPANY_FINANCIALS_PATH = "/api/v1/financials/company";
const PERMISSIONS_PATH_MARKER = "/me/permissions";
const PROJECTS_PATH_SUFFIX = "/projects/";
const SHORT_WINDOW_QUERY = "window=3m";

const FINANCIALS_ROUTE = "/financials";
const PROJECT_FINANCIALS_ROUTE = `/financials/${OVERRUN_PROJECT_ID}`;
const FINANCIALS_NAV_LABEL = "Financials";
const REPORTS_NAV_LABEL = "Reports";
const DENY_PANEL_TEST_ID = "financials-deny-panel";
const DENY_MESSAGE = "You do not have permission to view financials.";
const TREND_CHART_TEST_ID = "margin-trend-chart";
const NO_ELEMENTS = 0;
const NO_REQUESTS = 0;

async function seedAuth(page: Page) {
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);

  await page.route("**/api/auth/login", async (route: Route) =>
    route.fulfill({
      json: {
        user_id: "u1",
        company_id: "co-1",
        email: "sarah@ace.com",
        display_name: "Sarah Mitchell",
        company_name: "Ace",
        roles: ["admin"],
      },
    })
  );
}

interface FinanceMockOptions {
  permissions: string[];
  /** Every proxied financial path, in request order. A length of zero on a denied
   *  cold load is the load-bearing half of the SC3 keystone. */
  financialRequests: string[];
}

/** One proxy handler for every route these two pages touch. Branches are ordered
 *  most-specific-first: the trend path contains the drill-down path, which in turn
 *  contains the projects prefix. */
async function mockFinanceRoutes(page: Page, options: FinanceMockOptions) {
  await seedAuth(page);

  await page.route(PROXY_GLOB, async (route: Route) => {
    const path = new URL(route.request().url()).searchParams.get("path") ?? "";
    if (path.includes(FINANCIALS_PATH_MARKER)) options.financialRequests.push(path);

    if (path.includes(TREND_PATH_MARKER)) {
      const isShortWindow = path.includes(SHORT_WINDOW_QUERY);
      return route.fulfill({ json: isShortWindow ? MARGIN_TREND_3M : MARGIN_TREND_12M });
    }
    if (path.endsWith(FINANCIALS_PATH_MARKER) && path.includes(PROJECTS_PATH_SUFFIX)) {
      return route.fulfill({ json: PROJECT_FINANCIALS });
    }
    if (path === COMPANY_FINANCIALS_PATH) {
      return route.fulfill({ json: COMPANY_FINANCIALS });
    }
    if (path.includes(PERMISSIONS_PATH_MARKER)) {
      return route.fulfill({ json: { permissions: options.permissions } });
    }
    // Shell chatter (projects list, alerts, counters) — nothing these two routes
    // render reads it, and an empty collection keeps the console quiet.
    return route.fulfill({ json: [] });
  });
}

/**
 * Redux `isAuthenticated` is set only by the login page (the 32-04 lesson), so a
 * hard `page.goto` leaves `usePermissions` disabled and every finance surface
 * correctly denied. The permitted-user path must therefore log in through the UI
 * and then SPA-navigate.
 */
async function loginThroughUi(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
}

async function gotoFinancialsViaSidebar(page: Page) {
  await page.getByRole("link", { name: FINANCIALS_NAV_LABEL }).click();
  await page.waitForURL(/\/financials$/);
}

test("nav item is absent without finance.view", async ({ page }) => {
  const financialRequests: string[] = [];
  await mockFinanceRoutes(page, {
    permissions: NON_FINANCE_PERMISSIONS,
    financialRequests,
  });

  await loginThroughUi(page);

  // Reports proves the sidebar itself rendered, so the missing Financials item is
  // the permission gate and not a nav that failed to mount.
  await expect(page.getByRole("link", { name: REPORTS_NAV_LABEL })).toBeVisible();
  await expect(page.getByRole("link", { name: FINANCIALS_NAV_LABEL })).toHaveCount(
    NO_ELEMENTS
  );
});

async function expectDeniedWithoutFetching(page: Page, financialRequests: string[]) {
  const denyPanel = page.getByTestId(DENY_PANEL_TEST_ID);
  await expect(denyPanel).toBeVisible();
  await expect(denyPanel).toHaveText(DENY_MESSAGE);
  expect(financialRequests).toHaveLength(NO_REQUESTS);
}

// Read this before changing the assertion below.
//
// A hard `page.goto` resets Redux, so `isAuthenticated` is false, `usePermissions`
// is disabled, and the deny panel would render for a PERMITTED user too. The
// assertion that carries weight here is therefore the ZERO captured
// /api/v1/financials/* requests: it proves no financial data is fetched or painted
// before permissions are known.
//
// Do NOT "fix" this into a permitted-user goto test. That would be a false green —
// it still passes with FinanceGate deleted.
test("direct navigation to /financials is denied and fetches nothing", async ({
  page,
}) => {
  const financialRequests: string[] = [];
  await mockFinanceRoutes(page, {
    permissions: NON_FINANCE_PERMISSIONS,
    financialRequests,
  });

  await page.goto(FINANCIALS_ROUTE);
  await expectDeniedWithoutFetching(page, financialRequests);

  await page.goto(PROJECT_FINANCIALS_ROUTE);
  await expectDeniedWithoutFetching(page, financialRequests);
});

test("finance user reaches both routes by SPA navigation", async ({ page }) => {
  const financialRequests: string[] = [];
  await mockFinanceRoutes(page, {
    permissions: FINANCE_PERMISSIONS,
    financialRequests,
  });

  await loginThroughUi(page);
  await gotoFinancialsViaSidebar(page);

  await expect(
    page.getByRole("heading", { level: 1, name: FINANCIALS_NAV_LABEL })
  ).toBeVisible();
  await expect(page.getByTestId(DENY_PANEL_TEST_ID)).toHaveCount(NO_ELEMENTS);

  await page.getByTestId(`attention-row-${OVERRUN_PROJECT_ID}`).click();
  await page.waitForURL(new RegExp(`/financials/${OVERRUN_PROJECT_ID}$`));

  await expect(page.getByTestId(TREND_CHART_TEST_ID)).toBeVisible();
  await expect(page.getByTestId(DENY_PANEL_TEST_ID)).toHaveCount(NO_ELEMENTS);
  // The mirror image of the denial test: a permitted user does fetch money data.
  expect(financialRequests.length).toBeGreaterThan(NO_REQUESTS);
});
