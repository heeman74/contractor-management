import { test, expect, type Page, type Route } from "@playwright/test";

// E2E: the AI profitability finding on /financials/[projectId] (FINAI-02, SC2/SC3,
// 36-UI-SPEC states 1, 4-16 and 19). Follows the phase-33/34/35 recipe — mock
// /api/proxy, log in through the UI so Redux auth + permissions populate, then
// SPA-navigate via the sidebar and the attention list.
//
// The AI prose is never retyped in an assertion: every narrative and corrective
// action is read back off FINDING_FIXTURE, so a fixture edit can never leave a
// stale sentence asserted somewhere else in this file.

const FINANCE_PERMISSIONS = ["projects.view", "finance.view"];

const PROJECT_ID = "proj-f-1";
const PROJECT_NAME = "Downtown Remodel";

interface FindingFixture {
  id: string;
  project_id: string;
  severity: "warning" | "critical";
  narrative: string;
  corrective_action: string;
  revenue_basis: string;
  labor_included: boolean;
  found_on: string;
  last_confirmed_on: string;
}

/** A re-confirmed warning finding: found one week, still open the next, grounded
 *  against a mixed revenue basis with rated labor inside the analyzed payload. */
const FINDING_FIXTURE: FindingFixture = {
  id: "finding-f-1",
  project_id: PROJECT_ID,
  severity: "warning",
  narrative:
    "Cumulative margin has fallen to 12.4% as materials on the plumbing scope ran $3,200 past the approved quote allowance.",
  corrective_action:
    "Rebill the plumbing change order or renegotiate supplier pricing before drywall starts — $3,200 is currently absorbed.",
  revenue_basis: "mixed",
  labor_included: true,
  found_on: "2026-07-22",
  last_confirmed_on: "2026-07-29",
};

/** The same finding one band up. Only the chip may change — the card chrome is
 *  band-independent, so a critical finding can never read as a broken page. */
const CRITICAL_FINDING_FIXTURE: FindingFixture = {
  ...FINDING_FIXTURE,
  severity: "critical",
};

interface MarginFixture {
  revenue: string | null;
  revenue_basis: string;
  margin: string | null;
  margin_percent: string | null;
  incomplete: boolean;
  incomplete_reasons: string[];
}

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

/** The figures the narrative cites: 12.4% margin on a mixed basis. */
const PROJECT_MARGIN = {
  revenue: "52000.00",
  revenue_basis: "mixed",
  margin: "6480.00",
  margin_percent: "12.4",
};

const PROJECT_COST = "45520.00";
const SCOPE_SPEND = "8200.00";

const PROJECT_BUDGET = {
  budget_id: "budget-f-1",
  total: "50000.00",
  spent: PROJECT_COST,
  remaining: "4480.00",
  percent_used: "91.0",
};

const SCOPE_BUDGET = {
  budget_id: "budget-f-2",
  total: "10000.00",
  spent: SCOPE_SPEND,
  remaining: "1800.00",
  percent_used: "82.0",
};

const COMPANY_FINANCIALS = {
  portfolio: {
    cost: PROJECT_COST,
    quoted_revenue: "18400.00",
    incomplete_project_count: 0,
    margin: marginFixture(PROJECT_MARGIN),
  },
  projects: [
    {
      project_id: PROJECT_ID,
      name: PROJECT_NAME,
      status: "active",
      cost: PROJECT_COST,
      margin: marginFixture(PROJECT_MARGIN),
      budget: PROJECT_BUDGET,
    },
  ],
  attention: [
    {
      project_id: PROJECT_ID,
      project_name: PROJECT_NAME,
      project_status: "active",
      tier: "warning",
      anchor_label: PROJECT_NAME,
      spent: SCOPE_BUDGET.spent,
      budget_total: SCOPE_BUDGET.total,
      percent_used: SCOPE_BUDGET.percent_used,
    },
  ],
};

/** `incomplete` is the one shipped boolean the card reads to choose its empty
 *  state, so it is the only thing this fixture varies. */
function projectFinancialsFixture(incompleteCostData: boolean) {
  return {
    project_id: PROJECT_ID,
    name: PROJECT_NAME,
    status: "active",
    breakdown: {
      categories: [
        { category_id: "cat-materials", category_name: "Materials", total: "27600.00" },
        { category_id: "cat-sub", category_name: "Subcontractor", total: "9000.00" },
      ],
      labor: {
        total: "8920.00",
        rated_seconds: 288000,
        unrated_seconds: 0,
        basis: "unburdened",
      },
      labor_tracked_at_job_level: false,
      grand_total: PROJECT_COST,
      margin: marginFixture({
        ...PROJECT_MARGIN,
        incomplete: incompleteCostData,
        incomplete_reasons: incompleteCostData ? ["unrated_labor"] : [],
      }),
      budget: PROJECT_BUDGET,
    },
    scopes: [
      {
        trade_scope_id: "scope-f-1",
        trade_name: "Plumbing",
        spent: SCOPE_SPEND,
        budget: SCOPE_BUDGET,
      },
    ],
  };
}

const MARGIN_TREND = {
  project_id: PROJECT_ID,
  window: "12m",
  buckets: [
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
    { month: "2026-07", cost: PROJECT_COST, margin: marginFixture(PROJECT_MARGIN) },
  ],
};

const PROXY_PATHNAME = "/api/proxy";
const PROXY_GLOB = "**/api/proxy**";
const FINANCIALS_PATH_MARKER = "/financials";
const FINDING_PATH_MARKER = "/financials/finding";
const TREND_PATH_MARKER = "/financials/trend";
const COMPANY_FINANCIALS_PATH = "/api/v1/financials/company";
const PERMISSIONS_PATH_MARKER = "/me/permissions";
const PROJECTS_PATH_SUFFIX = "/projects/";

const FINANCIALS_NAV_LABEL = "Financials";

const CARD_TEST_ID = "profitability-finding";
const SEVERITY_TEST_ID = "profitability-finding-severity";
const DATE_TEST_ID = "profitability-finding-date";
const NARRATIVE_TEST_ID = "profitability-finding-narrative";
const ACTION_TEST_ID = "profitability-finding-action";
const BASIS_NOTE_TEST_ID = "profitability-finding-basis-note";
const LABOR_NOTE_TEST_ID = "profitability-finding-labor-note";
const DISCLOSURE_TEST_ID = "profitability-finding-disclosure";
const EMPTY_TEST_ID = "profitability-finding-empty";

const TREND_CARD_LABEL = "Margin Trend chart";

// Verbatim copy from the 36-UI-SPEC copywriting contract. The frame is locked
// byte-for-byte; the AI-authored prose inside it is only ever read back off the
// fixture, never retyped.
const WARNING_CHIP_LABEL = "Margin warning";
const CRITICAL_CHIP_LABEL = "Margin critical";
const DATE_LINE = "Found Jul 22, 2026 · Last confirmed Jul 29, 2026";
const SUGGESTED_ACTION_EYEBROW = "SUGGESTED ACTION";
const MIXED_BASIS_CAPTION = "Includes revenue from approved quotes — not yet invoiced.";
const UNBURDENED_LABOR_CAPTION =
  "Unburdened labor: Wage cost only — excludes payroll tax, insurance, overhead.";
const DISCLOSURE_LINE =
  "AI-written from this project's recorded figures — every number is from your data, never an AI estimate.";
const EMPTY_HEADING = "No margin erosion flagged";
const EMPTY_BODY =
  "A nightly AI review posts a finding here when this project's margin starts to slip.";
const INCOMPLETE_EMPTY_HEADING = "Not analyzed — incomplete cost data";
const INCOMPLETE_EMPTY_BODY =
  "AI skips projects with missing or unrated costs, so a finding can never rest on understated numbers.";

/** The card chrome is band-independent: neither red token may reach the root. */
const FORBIDDEN_SEVERITY_CHROME = ["border-red", "bg-red"];

const SERVER_ERROR_STATUS = 500;
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
  /** `null` renders an empty state; the fixture renders the finding itself. */
  finding?: FindingFixture | null;
  /** The state-19 outage: the finding path 500s while every other route is healthy. */
  findingFails?: boolean;
  incompleteCostData?: boolean;
}

/** One proxy handler for every route these pages touch. Branches are ordered
 *  most-specific-first: the finding and trend paths both extend the drill-down
 *  path, which in turn contains the projects prefix. */
async function mockFinanceRoutes(page: Page, options: FinanceMockOptions) {
  const {
    permissions,
    finding = FINDING_FIXTURE,
    findingFails = false,
    incompleteCostData = false,
  } = options;

  await seedAuth(page);

  await page.route(PROXY_GLOB, async (route: Route) => {
    const path = new URL(route.request().url()).searchParams.get("path") ?? "";

    if (path.includes(FINDING_PATH_MARKER)) {
      if (findingFails) return route.fulfill({ status: SERVER_ERROR_STATUS, json: {} });
      return route.fulfill({ json: finding });
    }
    if (path.includes(TREND_PATH_MARKER)) {
      return route.fulfill({ json: MARGIN_TREND });
    }
    if (path.endsWith(FINANCIALS_PATH_MARKER) && path.includes(PROJECTS_PATH_SUFFIX)) {
      return route.fulfill({ json: projectFinancialsFixture(incompleteCostData) });
    }
    if (path === COMPANY_FINANCIALS_PATH) {
      return route.fulfill({ json: COMPANY_FINANCIALS });
    }
    if (path.includes(PERMISSIONS_PATH_MARKER)) {
      return route.fulfill({ json: { permissions } });
    }
    // Shell chatter (projects list, alerts, counters) — nothing these routes
    // render reads it, and an empty collection keeps the console quiet.
    return route.fulfill({ json: [] });
  });
}

/**
 * Every proxied financial path the browser actually requests, in request order.
 *
 * This listens on the browser's own request stream rather than inside the route
 * handler, so it captures the call even if a future handler stops matching it.
 * Install it BEFORE any navigation.
 */
function captureFinancialRequests(page: Page): string[] {
  const requestedPaths: string[] = [];
  page.on("request", (request) => {
    const url = new URL(request.url());
    if (url.pathname !== PROXY_PATHNAME) return;
    const path = url.searchParams.get("path") ?? "";
    if (path.includes(FINANCIALS_PATH_MARKER)) requestedPaths.push(path);
  });
  return requestedPaths;
}

function findingRequestsIn(requestedPaths: string[]): string[] {
  return requestedPaths.filter((path) => path.includes(FINDING_PATH_MARKER));
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

/** The drill-down is reached the way a user reaches it — sidebar, then the
 *  attention row — never by a hard navigation to /financials/<id>. */
async function openDrillDownAsFinanceUser(page: Page) {
  await loginThroughUi(page);
  await page.getByRole("link", { name: FINANCIALS_NAV_LABEL }).click();
  await page.waitForURL(/\/financials$/);
  await page.getByTestId(`attention-row-${PROJECT_ID}`).click();
  await page.waitForURL(new RegExp(`/financials/${PROJECT_ID}$`));
}

test("finance user sees the AI profitability finding on the project drill-down", async ({
  page,
}) => {
  const financialRequests = captureFinancialRequests(page);
  await mockFinanceRoutes(page, { permissions: FINANCE_PERMISSIONS });

  await openDrillDownAsFinanceUser(page);

  await expect(page.getByTestId(CARD_TEST_ID)).toBeVisible();
  await expect(page.getByTestId(SEVERITY_TEST_ID)).toHaveText(WARNING_CHIP_LABEL);
  await expect(page.getByTestId(DATE_TEST_ID)).toHaveText(DATE_LINE);

  await expect(page.getByTestId(NARRATIVE_TEST_ID)).toContainText(
    FINDING_FIXTURE.narrative
  );
  await expect(page.getByText(SUGGESTED_ACTION_EYEBROW)).toBeVisible();
  await expect(page.getByTestId(ACTION_TEST_ID)).toContainText(
    FINDING_FIXTURE.corrective_action
  );

  await expect(page.getByTestId(BASIS_NOTE_TEST_ID)).toHaveText(MIXED_BASIS_CAPTION);
  await expect(page.getByTestId(LABOR_NOTE_TEST_ID)).toHaveText(
    UNBURDENED_LABOR_CAPTION
  );
  await expectDisclosureIsTheLastCaption(page);

  await expectFindingAboveTheMarginTrend(page);

  // The mirror image of the denial keystone: a permitted user does fetch the
  // finding, so a zero counter there means the gate held, not that the route
  // silently stopped being requested at all.
  expect(findingRequestsIn(financialRequests).length).toBeGreaterThan(NO_REQUESTS);
});

/** The disclosure qualifies every caption above it, so it is always rendered
 *  last — nothing may be appended below it. */
async function expectDisclosureIsTheLastCaption(page: Page) {
  const disclosure = page.getByTestId(DISCLOSURE_TEST_ID);
  await expect(disclosure).toHaveText(DISCLOSURE_LINE);

  const hasCaptionBelowIt = await disclosure.evaluate(
    (node) => node.nextElementSibling !== null
  );
  expect(hasCaptionBelowIt).toBe(false);
}

/** Reading order is figures → interpretation → evidence: the finding interprets
 *  the tiles above it and the trend chart below it is the evidence it describes. */
async function expectFindingAboveTheMarginTrend(page: Page) {
  const trendCard = page.locator(`[aria-label="${TREND_CARD_LABEL}"]`);
  await expect(trendCard).toBeVisible();

  const findingBox = await page.getByTestId(CARD_TEST_ID).boundingBox();
  const trendBox = await trendCard.boundingBox();
  if (!findingBox || !trendBox) throw new Error("A finance card has no bounding box");

  expect(findingBox.y).toBeLessThan(trendBox.y);
}

test("a critical finding renders the red chip and unchanged card chrome", async ({
  page,
}) => {
  await mockFinanceRoutes(page, {
    permissions: FINANCE_PERMISSIONS,
    finding: CRITICAL_FINDING_FIXTURE,
  });

  await openDrillDownAsFinanceUser(page);

  await expect(page.getByTestId(SEVERITY_TEST_ID)).toHaveText(CRITICAL_CHIP_LABEL);
  await expect(page.getByTestId(NARRATIVE_TEST_ID)).toContainText(
    CRITICAL_FINDING_FIXTURE.narrative
  );

  // Only the chip carries the band. A red border or a tinted surface would make
  // a finding card indistinguishable from the page-level error panel.
  const cardClasses = (await page.getByTestId(CARD_TEST_ID).getAttribute("class")) ?? "";
  for (const forbidden of FORBIDDEN_SEVERITY_CHROME) {
    expect(cardClasses).not.toContain(forbidden);
  }
});

async function expectEmptyState(page: Page, heading: string, body: string) {
  const emptyState = page.getByTestId(EMPTY_TEST_ID);
  await expect(emptyState).toBeVisible();
  await expect(emptyState).toContainText(heading);
  await expect(emptyState).toContainText(body);

  await expect(page.getByTestId(SEVERITY_TEST_ID)).toHaveCount(NO_ELEMENTS);
  await expect(page.getByTestId(NARRATIVE_TEST_ID)).toHaveCount(NO_ELEMENTS);
}

test("no open finding on an incomplete-cost project says why the AI stayed silent", async ({
  page,
}) => {
  await mockFinanceRoutes(page, {
    permissions: FINANCE_PERMISSIONS,
    finding: null,
    incompleteCostData: true,
  });

  await openDrillDownAsFinanceUser(page);

  // Pitfall 9: an unqualified "nothing flagged" on a project the AI never looked
  // at is exactly the false comfort this variant exists to prevent.
  await expectEmptyState(page, INCOMPLETE_EMPTY_HEADING, INCOMPLETE_EMPTY_BODY);
});

test("no open finding on a complete-cost project reads as no erosion flagged", async ({
  page,
}) => {
  await mockFinanceRoutes(page, {
    permissions: FINANCE_PERMISSIONS,
    finding: null,
    incompleteCostData: false,
  });

  await openDrillDownAsFinanceUser(page);

  await expectEmptyState(page, EMPTY_HEADING, EMPTY_BODY);
});
