import { test, expect, type Page, type Route } from "@playwright/test";

// E2E: margin section on the job, trade-scope, and project Costs surfaces
// (MARG-01/02/03, 33-UI-SPEC states 1-5, 7, 12). Follows the repo convention —
// mock /api/proxy, log in through the UI so Redux auth + permissions populate,
// then SPA-navigate to the surface under test.

const INVOICED_MARGIN = {
  revenue: "20000.00",
  revenue_basis: "invoiced",
  margin: "4200.00",
  margin_percent: "21.0",
  incomplete: false,
  incomplete_reasons: [],
};
const QUOTED_MARGIN = { ...INVOICED_MARGIN, revenue_basis: "quoted" };
const MIXED_MARGIN = { ...INVOICED_MARGIN, revenue_basis: "mixed" };
const FLAGGED_MARGIN = {
  revenue: "2000.00",
  revenue_basis: "invoiced",
  margin: "2000.00",
  margin_percent: "100.0",
  incomplete: true,
  incomplete_reasons: ["no_cost_data"],
};
const NO_REVENUE_MARGIN = {
  revenue: null,
  revenue_basis: "none",
  margin: null,
  margin_percent: null,
  incomplete: false,
  incomplete_reasons: [],
};

const JOB = {
  id: "job-m-1",
  company_id: "co-1",
  description: "Kitchen sink repair",
  trade_type: "Plumbing",
  status: "in_progress",
  status_history: [],
  priority: "medium",
  client_id: null,
  client_name: null,
  contractor_id: null,
  contractor_name: null,
  purchase_order_number: null,
  external_reference: null,
  tags: [],
  notes: null,
  estimated_duration_minutes: null,
  scheduled_completion_date: null,
  gps_latitude: null,
  gps_longitude: null,
  gps_address: null,
  version: 1,
  created_at: "2026-07-01T00:00:00Z",
  updated_at: "2026-07-01T00:00:00Z",
};

const PROJECT = {
  id: "proj-m-1",
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
  id: "scope-m-1",
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

const CATEGORIES = [
  { id: "cat-materials", name: "Materials", is_system: true },
  { id: "cat-sub", name: "Subcontractor", is_system: true },
];

const JOB_BREAKDOWN = {
  categories: [{ category_id: "c1", category_name: "materials", total: "150.00" }],
  labor: {
    total: "240.00",
    rated_seconds: 28800,
    unrated_seconds: 0,
    basis: "unburdened",
  },
  labor_tracked_at_job_level: false,
  grand_total: "390.00",
  margin: INVOICED_MARGIN,
};

// Pitfall-9 legacy job: revenue exists but zero costs — the honesty flag must show.
const LEGACY_JOB_BREAKDOWN = {
  categories: [],
  labor: { total: "0.00", rated_seconds: 0, unrated_seconds: 0, basis: "unburdened" },
  labor_tracked_at_job_level: false,
  grand_total: "0.00",
  margin: FLAGGED_MARGIN,
};

const QUOTED_SCOPE_BREAKDOWN = {
  categories: [{ category_id: "c1", category_name: "materials", total: "150.00" }],
  labor: null,
  labor_tracked_at_job_level: true,
  grand_total: "150.00",
  margin: QUOTED_MARGIN,
};

const NO_REVENUE_SCOPE_BREAKDOWN = {
  ...QUOTED_SCOPE_BREAKDOWN,
  margin: NO_REVENUE_MARGIN,
};

const MIXED_PROJECT_ROLLUP = {
  project_id: PROJECT.id,
  total: "150.00",
  entries: [],
  categories: [{ category_id: "c1", category_name: "materials", total: "150.00" }],
  labor: null,
  grand_total: "150.00",
  margin: MIXED_MARGIN,
};

interface MockOptions {
  permissions: string[];
  jobBreakdown?: Record<string, unknown>;
}

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

async function mockJobApi(page: Page, options: MockOptions) {
  await seedAuth(page);

  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: options.permissions } });
    if (method === "GET" && path.includes("/cost-breakdown"))
      return route.fulfill({ json: options.jobBreakdown ?? JOB_BREAKDOWN });
    if (method === "GET" && path.includes("/cost-categories"))
      return route.fulfill({ json: CATEGORIES });
    if (method === "GET" && path === `/api/v1/jobs/${JOB.id}`)
      return route.fulfill({ json: JOB });
    if (method === "GET" && path.startsWith("/api/v1/jobs?"))
      return route.fulfill({ json: [JOB] });
    // Everything else the job page pulls (notes, time entries, quotes, ...) —
    // 32-04 recipe: the job surface fetches too many side endpoints to enumerate.
    return route.fulfill({ json: [] });
  });
}

interface ProjectMockOptions {
  permissions: string[];
  scopeBreakdown: Record<string, unknown>;
  projectRollup: Record<string, unknown>;
}

async function mockProjectApi(page: Page, options: ProjectMockOptions) {
  await seedAuth(page);

  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: options.permissions } });
    if (method === "GET" && path.endsWith("/projects/"))
      return route.fulfill({ json: [PROJECT] });
    if (method === "GET" && path.includes("/assignments"))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes(`/jobs/?project_id=${PROJECT.id}`))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes("/cost-breakdown"))
      return route.fulfill({ json: options.scopeBreakdown });
    if (method === "GET" && path.includes("/trade-scopes"))
      return route.fulfill({ json: [TRADE_SCOPE] });
    if (method === "GET" && path.includes("/tasks"))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes(`/projects/${PROJECT.id}/cost-entries`))
      return route.fulfill({ json: options.projectRollup });
    if (method === "GET" && path.includes("/cost-categories"))
      return route.fulfill({ json: CATEGORIES });
    if (method === "GET" && path.includes("/cost-entries"))
      return route.fulfill({ json: [] });
    return route.fulfill({ status: 404, json: { detail: `unmatched ${method} ${path}` } });
  });
}

async function loginThroughUi(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
}

async function openJobDetail(page: Page) {
  await page.getByRole("link", { name: "Jobs" }).click();
  const jobRow = page.locator("tbody tr").first();
  await expect(jobRow).toBeVisible();
  await jobRow.click();
  await page.waitForURL(`**/jobs/${JOB.id}`);
  await expect(page.getByRole("heading", { name: JOB.description })).toBeVisible();
}

async function openProjects(page: Page) {
  await page.getByRole("link", { name: "Projects" }).click();
}

async function openTradeScope(page: Page) {
  await page.getByRole("button", { name: "Expand project" }).click();
  await page.getByRole("treeitem", { name: /plumbing/i }).click();
}

test("job detail shows an invoiced margin with no caption and no chip", async ({
  page,
}) => {
  await mockJobApi(page, {
    permissions: ["jobs.view", "finance.view", "finance.manage"],
  });

  await loginThroughUi(page);
  await openJobDetail(page);

  await expect(page.getByTestId("margin-section")).toBeVisible();
  await expect(page.getByTestId("margin-revenue")).toHaveText("$20000.00");
  await expect(page.getByTestId("margin-figure")).toHaveText("$4200.00 · 21%");
  await expect(page.getByTestId("margin-basis-caption")).toHaveCount(0);
  await expect(page.getByTestId("margin-incomplete-chip")).toHaveCount(0);
});

test("trade-scope detail shows the quoted-basis caption", async ({ page }) => {
  await mockProjectApi(page, {
    permissions: ["projects.view", "projects.edit", "finance.view", "finance.manage"],
    scopeBreakdown: QUOTED_SCOPE_BREAKDOWN,
    projectRollup: { project_id: PROJECT.id, total: "0", entries: [] },
  });

  await loginThroughUi(page);
  await openProjects(page);
  await openTradeScope(page);

  await expect(page.getByTestId("margin-section")).toBeVisible();
  await expect(page.getByTestId("margin-basis-caption")).toHaveText(
    "Based on approved quote — not yet invoiced."
  );
});

test("project Costs card shows the mixed-basis caption, and a no-revenue scope shows the neutral note", async ({
  page,
}) => {
  await mockProjectApi(page, {
    permissions: ["projects.view", "projects.edit", "finance.view", "finance.manage"],
    scopeBreakdown: NO_REVENUE_SCOPE_BREAKDOWN,
    projectRollup: MIXED_PROJECT_ROLLUP,
  });

  await loginThroughUi(page);
  await openProjects(page);

  await expect(page.getByTestId("margin-section")).toBeVisible();
  await expect(page.getByTestId("margin-basis-caption")).toHaveText(
    "Includes approved quote amounts not yet invoiced."
  );
  await expect(page.getByTestId("margin-figure")).toHaveText("$4200.00 · 21%");

  await openTradeScope(page);

  await expect(page.getByTestId("margin-no-revenue")).toHaveText(
    "No revenue recorded — margin will appear once an invoice or approved quote exists."
  );
});

test("KEYSTONE: legacy job with revenue and zero costs still shows the flagged margin", async ({
  page,
}) => {
  await mockJobApi(page, {
    permissions: ["jobs.view", "finance.view", "finance.manage"],
    jobBreakdown: LEGACY_JOB_BREAKDOWN,
  });

  await loginThroughUi(page);
  await openJobDetail(page);

  await expect(page.getByTestId("margin-section")).toBeVisible();
  await expect(page.getByTestId("margin-incomplete-chip")).toHaveText(
    "Incomplete cost data"
  );
  await expect(page.getByTestId("margin-incomplete-caption")).toHaveText(
    "Margin may overstate profit — some costs are missing or unrated."
  );
  await expect(page.getByTestId("margin-figure")).toHaveText("$2000.00 · 100%");
});

test("no margin renders anywhere without finance.view", async ({ page }) => {
  await mockJobApi(page, {
    permissions: ["jobs.view", "projects.view"],
  });

  await loginThroughUi(page);
  await openJobDetail(page);

  await expect(page.getByRole("main").getByText("Total Spent")).toHaveCount(0);
  await expect(page.getByTestId("margin-section")).toHaveCount(0);
  await expect(page.getByTestId("margin-figure")).toHaveCount(0);
});
