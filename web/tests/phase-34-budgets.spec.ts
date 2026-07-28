import { test, expect, type Page, type Route } from "@playwright/test";

// E2E: budget set/edit/remove flow on the trade-scope and project Costs
// surfaces plus the monitoring Alert panel (BUDG-01/BUDG-03, 34-UI-SPEC
// states 2-6 and 11). Follows the phase-33 recipe — mock /api/proxy, log in
// through the UI so Redux auth + permissions populate, then SPA-navigate.

const PROJECT = {
  id: "proj-b-1",
  company_id: "co-1",
  name: "Downtown Remodel",
  description: null,
  address: null,
  client_id: null,
  target_start_date: null,
  target_end_date: null,
  status: "active",
  status_history: [],
  version: 1,
  created_at: "2026-07-25T00:00:00Z",
  updated_at: "2026-07-25T00:00:00Z",
  deleted_at: null,
  trade_scopes: [],
};

const TRADE_SCOPE = {
  id: "scope-b-1",
  project_id: PROJECT.id,
  trade_catalog_id: null,
  trade_name: "Plumbing",
  trade_color: "#2563eb",
  contractor_id: null,
  status: "in_progress",
  version: 1,
  created_at: "2026-07-25T00:00:00Z",
  updated_at: "2026-07-25T00:00:00Z",
};

const CATEGORIES = [{ id: "cat-materials", name: "Materials", is_system: true }];

interface BudgetBlock {
  budget_id: string;
  total: string;
  spent: string;
  remaining: string;
  percent_used: string;
}

const WARNING_BUDGET: BudgetBlock = {
  budget_id: "budget-1",
  total: "10000.00",
  spent: "8200.00",
  remaining: "1800.00",
  percent_used: "82.0",
};

const OVERRUN_PROJECT_BUDGET: BudgetBlock = {
  budget_id: "budget-2",
  total: "10000.00",
  spent: "11200.00",
  remaining: "-1200.00",
  percent_used: "112.0",
};

const FULL_PERMISSIONS = [
  "projects.view",
  "projects.edit",
  "finance.view",
  "finance.manage",
];

function scopeBreakdown(budget: BudgetBlock | null) {
  return {
    categories: [
      { category_id: "c1", category_name: "materials", total: "8200.00" },
    ],
    labor: null,
    labor_tracked_at_job_level: true,
    grand_total: "8200.00",
    margin: null,
    budget,
  };
}

function projectRollup(budget: BudgetBlock | null) {
  return {
    project_id: PROJECT.id,
    total: "11200.00",
    entries: [],
    categories: [
      { category_id: "c1", category_name: "materials", total: "11200.00" },
    ],
    labor: null,
    grand_total: "11200.00",
    margin: null,
    budget,
  };
}

const WARNING_ALERT = {
  id: "alert-1",
  project_id: PROJECT.id,
  trade_scope_id: TRADE_SCOPE.id,
  severity: "warning",
  alert_type: "budget_warning",
  days_behind: null,
  impact_text:
    "Downtown Remodel — Plumbing scope has spent $8,200 of its $10,000 budget (82%).",
  remediation_text: null,
  affected_scope_ids: [],
  is_read: false,
  rescheduling_payload: null,
  rescheduling_accepted: null,
  created_at: "2026-07-27T00:00:00Z",
};

const OVERRUN_ALERT = {
  ...WARNING_ALERT,
  id: "alert-2",
  trade_scope_id: null,
  severity: "critical",
  alert_type: "budget_overrun",
  impact_text:
    "Downtown Remodel has exceeded its $10,000 budget — $11,200 spent (112%).",
};

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

interface BudgetMockState {
  scopeBudget: BudgetBlock | null;
  projectBudget: BudgetBlock | null;
}

/** Stateful proxy mock: budget mutations update the state the breakdown and
 *  rollup responses are built from, so invalidation-driven refetches show the
 *  post-mutation rows. Routes are matched most-specific-first. */
async function mockBudgetApi(page: Page, state: BudgetMockState) {
  await seedAuth(page);

  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "POST" && path === "/api/v1/budgets/") {
      const body = req.postDataJSON() as { total: string };
      state.scopeBudget = {
        ...WARNING_BUDGET,
        budget_id: "budget-created",
        total: Number(body.total).toFixed(2),
      };
      return route.fulfill({ status: 201, json: state.scopeBudget });
    }
    if (method === "DELETE" && path.startsWith("/api/v1/budgets/")) {
      state.scopeBudget = null;
      return route.fulfill({ status: 200, json: null });
    }
    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: FULL_PERMISSIONS } });
    if (method === "GET" && path.endsWith("/projects/"))
      return route.fulfill({ json: [PROJECT] });
    if (method === "GET" && path.includes("/assignments"))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes(`/jobs/?project_id=${PROJECT.id}`))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes("/cost-breakdown"))
      return route.fulfill({ json: scopeBreakdown(state.scopeBudget) });
    if (method === "GET" && path.includes("/trade-scopes"))
      return route.fulfill({ json: [TRADE_SCOPE] });
    if (method === "GET" && path.includes("/tasks"))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes(`/projects/${PROJECT.id}/cost-entries`))
      return route.fulfill({ json: projectRollup(state.projectBudget) });
    if (method === "GET" && path.includes("/cost-categories"))
      return route.fulfill({ json: CATEGORIES });
    if (method === "GET" && path.includes("/cost-entries"))
      return route.fulfill({ json: [] });
    return route.fulfill({
      status: 404,
      json: { detail: `unmatched ${method} ${path}` },
    });
  });
}

async function mockMonitoringApi(page: Page) {
  await seedAuth(page);

  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: FULL_PERMISSIONS } });
    if (method === "GET" && path.includes("/dashboard/alerts"))
      return route.fulfill({ json: [WARNING_ALERT, OVERRUN_ALERT] });
    if (method === "GET" && path.startsWith("/api/v1/dashboard"))
      return route.fulfill({ json: [] });
    return route.fulfill({ json: [] });
  });
}

async function loginThroughUi(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
}

async function openProjects(page: Page) {
  await page.getByRole("link", { name: "Projects" }).click();
}

async function openTradeScope(page: Page) {
  await page.getByRole("button", { name: "Expand project" }).click();
  await page.getByRole("treeitem", { name: /plumbing/i }).click();
}

test("trade-scope Costs shows the budget triad with the dotted spent figure", async ({
  page,
}) => {
  await mockBudgetApi(page, { scopeBudget: WARNING_BUDGET, projectBudget: null });

  await loginThroughUi(page);
  await openProjects(page);
  await openTradeScope(page);

  await expect(page.getByTestId("budget-amount")).toBeVisible();
  await expect(page.getByTestId("budget-spent")).toBeVisible();
  await expect(page.getByTestId("budget-remaining")).toBeVisible();
  await expect(page.getByTestId("budget-spent")).toContainText(" · ");
});

test("setting a budget closes the dialog and the rows appear without a reload", async ({
  page,
}) => {
  await mockBudgetApi(page, { scopeBudget: null, projectBudget: null });

  await loginThroughUi(page);
  await openProjects(page);
  await openTradeScope(page);

  await expect(page.getByTestId("budget-amount")).toHaveCount(0);
  await page.getByTestId("budget-set-button").click();
  await expect(page.getByTestId("set-budget-dialog")).toBeVisible();

  await page.getByTestId("budget-amount-input").fill("10000");
  await page.getByRole("button", { name: "Set Budget" }).click();

  await expect(page.getByTestId("set-budget-dialog")).toHaveCount(0);
  await expect(page.getByTestId("budget-amount")).toHaveText("$10000.00");
  await expect(page.getByTestId("budget-spent")).toContainText(" · ");
});

test("removing a budget through edit → remove → confirm clears the rows", async ({
  page,
}) => {
  await mockBudgetApi(page, { scopeBudget: WARNING_BUDGET, projectBudget: null });

  await loginThroughUi(page);
  await openProjects(page);
  await openTradeScope(page);

  await page.getByTestId("budget-edit-button").click();
  await expect(page.getByTestId("set-budget-dialog")).toBeVisible();
  await expect(page.getByText("Edit budget — Plumbing scope")).toBeVisible();

  await page.getByTestId("budget-remove-button").click();
  await page.getByTestId("budget-remove-confirm").click();

  await expect(page.getByTestId("set-budget-dialog")).toHaveCount(0);
  await expect(page.getByTestId("budget-amount")).toHaveCount(0);
  await expect(page.getByTestId("budget-set-button")).toBeVisible();
});

test("warning band shows the chip; over-budget shows the negative remaining and no chip", async ({
  page,
}) => {
  await mockBudgetApi(page, {
    scopeBudget: WARNING_BUDGET,
    projectBudget: OVERRUN_PROJECT_BUDGET,
  });

  await loginThroughUi(page);
  await openProjects(page);

  await expect(page.getByTestId("budget-remaining")).toHaveText("-$1200.00");
  await expect(page.getByTestId("budget-warning-chip")).toHaveCount(0);

  await openTradeScope(page);

  await expect(page.getByTestId("budget-warning-chip")).toHaveText(
    "Nearing budget"
  );
});

test("monitoring panel header reads Alerts and budget alert cards render impact text", async ({
  page,
}) => {
  await mockMonitoringApi(page);

  await loginThroughUi(page);
  await page.getByRole("link", { name: "Monitoring" }).click();

  await expect(
    page.getByRole("heading", { name: "Alerts", exact: true })
  ).toBeVisible();
  await expect(page.getByText(WARNING_ALERT.impact_text)).toBeVisible();
  await expect(page.getByText(OVERRUN_ALERT.impact_text)).toBeVisible();
  await expect(
    page.getByRole("button", { name: /accept rescheduling/i })
  ).toHaveCount(0);
});
