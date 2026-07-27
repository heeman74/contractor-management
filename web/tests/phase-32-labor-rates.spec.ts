import { test, expect, type Page, type Route } from "@playwright/test";

// E2E: gated Team-page labor-rate UI (COST-04, D-09).
// Follows the repo convention — mock /api/proxy, log in through the UI so
// Redux auth + permissions populate, then SPA-navigate to Team.

const USERS = [
  {
    id: "u1",
    company_id: "co-1",
    email: "sarah@ace.com",
    first_name: "Sarah",
    last_name: "Mitchell",
    phone: null,
    roles: ["project_manager"],
    version: 1,
    created_at: "2026-05-01T00:00:00Z",
    updated_at: "2026-05-01T00:00:00Z",
    deleted_at: null,
  },
  {
    id: "u2",
    company_id: "co-1",
    email: "mike@ace.com",
    first_name: "Mike",
    last_name: "Torres",
    phone: null,
    roles: ["worker"],
    version: 1,
    created_at: "2026-05-01T00:00:00Z",
    updated_at: "2026-05-01T00:00:00Z",
    deleted_at: null,
  },
];

const CURRENT_RATE = {
  id: "r1",
  user_id: "u1",
  hourly_cost: "45.00",
  effective_from: "2026-05-01",
  created_at: "2026-05-01T09:00:00Z",
  updated_at: "2026-05-01T09:00:00Z",
};

const SUPERSEDED_RATE = {
  id: "r0",
  user_id: "u1",
  hourly_cost: "44.00",
  effective_from: "2026-05-01",
  created_at: "2026-05-01T08:00:00Z",
  updated_at: "2026-05-01T08:00:00Z",
};

const FUTURE_RATE = {
  id: "r2",
  user_id: "u1",
  hourly_cost: "50.00",
  effective_from: "2027-01-01",
  created_at: "2026-06-01T09:00:00Z",
  updated_at: "2026-06-01T09:00:00Z",
};

interface MockOptions {
  permissions: string[];
}

async function mockApi(page: Page, captured: { body?: unknown }, options: MockOptions) {
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

  // Stateful u1 history — gains the created row after a successful POST.
  const rateHistory = [CURRENT_RATE, SUPERSEDED_RATE, FUTURE_RATE];

  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: options.permissions } });
    if (method === "GET" && path.endsWith("/users/"))
      return route.fulfill({ json: USERS });
    if (method === "POST" && path.endsWith("/labor-rates/")) {
      captured.body = req.postDataJSON();
      const body = captured.body as {
        user_id: string;
        hourly_cost: string;
        effective_from: string;
      };
      const created = {
        id: "r-new",
        user_id: body.user_id,
        hourly_cost: body.hourly_cost,
        effective_from: body.effective_from,
        created_at: "2026-07-27T00:00:00Z",
        updated_at: "2026-07-27T00:00:00Z",
      };
      rateHistory.push(created);
      return route.fulfill({ status: 201, json: created });
    }
    if (method === "GET" && path.includes("/labor-rates/") && path.includes("user_id=u1"))
      return route.fulfill({ json: rateHistory });
    if (method === "GET" && path.includes("/labor-rates/") && path.includes("user_id=u2"))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes("/labor-rates/"))
      return route.fulfill({ json: [CURRENT_RATE] });
    return route.fulfill({ status: 404, json: { detail: `unmatched ${method} ${path}` } });
  });
}

async function loginAndOpenTeam(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
  await page.getByRole("link", { name: "Team" }).click();
  await expect(page.getByRole("heading", { name: "Team" })).toBeVisible();
}

test("shows the Cost Rate column with the current rate for a finance.rates.manage user", async ({
  page,
}) => {
  const captured: { body?: unknown } = {};
  await mockApi(page, captured, {
    permissions: ["users.view", "finance.rates.manage"],
  });

  await loginAndOpenTeam(page);

  await expect(page.getByText("Cost Rate")).toBeVisible();
  await expect(page.getByTestId("cost-rate-u1")).toContainText("$45.00/hr");
  await expect(page.getByTestId("cost-rate-u2")).toContainText("—");
});

test("hides the Cost Rate column entirely without finance.rates.manage", async ({
  page,
}) => {
  const captured: { body?: unknown } = {};
  await mockApi(page, captured, { permissions: ["users.view"] });

  await loginAndOpenTeam(page);

  await expect(page.getByTestId("cost-rate-u1").or(page.getByTestId("cost-rate-u2"))).toHaveCount(0);
  await expect(page.getByText("Cost Rate")).toHaveCount(0);
  await expect(page.getByText("$45.00/hr")).toHaveCount(0);
  await expect(page.getByTestId("manage-rate-u1")).toHaveCount(0);
});

test("opens the rate dialog and shows the full history with future and superseded badges", async ({
  page,
}) => {
  const captured: { body?: unknown } = {};
  await mockApi(page, captured, {
    permissions: ["users.view", "finance.rates.manage"],
  });

  await loginAndOpenTeam(page);
  await page.getByTestId("manage-rate-u1").click();

  await expect(page.getByText("Labor rate — Sarah Mitchell")).toBeVisible();
  await expect(page.getByText("CURRENT RATE")).toBeVisible();
  await expect(page.getByTestId("current-rate-figure")).toContainText("$45.00/hr");
  await expect(page.getByText("Superseded")).toBeVisible();
  await expect(page.getByText(/^Starts /).first()).toBeVisible();
});

test("adds a rate and shows it in history without closing the dialog", async ({
  page,
}) => {
  const captured: { body?: unknown } = {};
  await mockApi(page, captured, {
    permissions: ["users.view", "finance.rates.manage"],
  });

  await loginAndOpenTeam(page);
  await page.getByTestId("manage-rate-u1").click();

  await page.getByLabel("Hourly rate").fill("52.50");
  await page.getByLabel("Effective date").fill("2026-08-01");
  await page.getByRole("button", { name: "Add Rate" }).click();

  await expect.poll(() => captured.body).toEqual({
    user_id: "u1",
    hourly_cost: "52.50",
    effective_from: "2026-08-01",
  });

  await expect(page.getByText("Labor rate — Sarah Mitchell")).toBeVisible();
  await expect(page.getByText("$52.50/hr").first()).toBeVisible();
});

test("shows the empty state for a member with no rate", async ({ page }) => {
  const captured: { body?: unknown } = {};
  await mockApi(page, captured, {
    permissions: ["users.view", "finance.rates.manage"],
  });

  await loginAndOpenTeam(page);
  await page.getByTestId("manage-rate-u2").click();

  await expect(page.getByText("Labor rate — Mike Torres")).toBeVisible();
  await expect(page.getByText("No rate set yet")).toBeVisible();
});

// ---------------------------------------------------------------------------
// 32-04 — cost breakdown surfaces (COST-06, D-05, D-06, D-08)
// ---------------------------------------------------------------------------

const BREAKDOWN_JOB = {
  id: "job-bd-1",
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

const BREAKDOWN_PROJECT = {
  id: "proj-bd-1",
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

const BREAKDOWN_SCOPE = {
  id: "scope-bd-1",
  project_id: BREAKDOWN_PROJECT.id,
  trade_catalog_id: null,
  trade_name: "Plumbing",
  trade_color: "#2563eb",
  contractor_id: null,
  status: "in_progress",
  version: 1,
  created_at: "2026-07-25T00:00:00Z",
  updated_at: "2026-07-25T00:00:00Z",
};

const PICKER_CATEGORIES = [
  { id: "cat-labor", name: "Labor", is_system: true },
  { id: "cat-materials", name: "Materials", is_system: true },
  { id: "cat-sub", name: "Subcontractor", is_system: true },
  { id: "cat-other", name: "Other", is_system: true },
];

const JOB_BREAKDOWN = {
  categories: [{ category_id: "c1", category_name: "materials", total: "150.00" }],
  labor: {
    total: "240.00",
    rated_seconds: 28800,
    unrated_seconds: 45000,
    basis: "unburdened",
  },
  labor_tracked_at_job_level: false,
  grand_total: "390.00",
};

const SCOPE_BREAKDOWN = {
  categories: [{ category_id: "c1", category_name: "materials", total: "150.00" }],
  labor: null,
  labor_tracked_at_job_level: true,
  grand_total: "150.00",
};

async function mockJobBreakdownApi(page: Page, options: MockOptions) {
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

  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: options.permissions } });
    if (method === "GET" && path.includes("/cost-breakdown"))
      return route.fulfill({ json: JOB_BREAKDOWN });
    if (method === "GET" && path.includes("/cost-categories"))
      return route.fulfill({ json: PICKER_CATEGORIES });
    if (method === "GET" && path === `/api/v1/jobs/${BREAKDOWN_JOB.id}`)
      return route.fulfill({ json: BREAKDOWN_JOB });
    if (method === "GET" && path.startsWith("/api/v1/jobs?"))
      return route.fulfill({ json: [BREAKDOWN_JOB] });
    // Everything else the job page pulls (notes, time entries, quotes, ...).
    return route.fulfill({ json: [] });
  });
}

async function loginAndOpenJobDetail(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
  await page.getByRole("link", { name: "Jobs" }).click();
  const jobRow = page.locator("tbody tr").first();
  await expect(jobRow).toBeVisible();
  await jobRow.click();
  await page.waitForURL(`**/jobs/${BREAKDOWN_JOB.id}`);
  await expect(
    page.getByRole("heading", { name: BREAKDOWN_JOB.description })
  ).toBeVisible();
}

async function mockTradeScopeBreakdownApi(page: Page, options: MockOptions) {
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

  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: options.permissions } });
    if (method === "GET" && path.endsWith("/projects/"))
      return route.fulfill({ json: [BREAKDOWN_PROJECT] });
    if (method === "GET" && path.includes("/assignments"))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes(`/jobs/?project_id=${BREAKDOWN_PROJECT.id}`))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes("/cost-breakdown"))
      return route.fulfill({ json: SCOPE_BREAKDOWN });
    if (method === "GET" && path.includes("/trade-scopes"))
      return route.fulfill({ json: [BREAKDOWN_SCOPE] });
    if (method === "GET" && path.includes("/tasks"))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes(`/projects/${BREAKDOWN_PROJECT.id}/cost-entries`))
      return route.fulfill({
        json: { project_id: BREAKDOWN_PROJECT.id, total: "0", entries: [] },
      });
    if (method === "GET" && path.includes("/cost-categories"))
      return route.fulfill({ json: PICKER_CATEGORIES });
    if (method === "GET" && path.includes("/cost-entries"))
      return route.fulfill({ json: [] });
    return route.fulfill({ status: 404, json: { detail: `unmatched ${method} ${path}` } });
  });
}

async function loginAndOpenTradeScope(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
  await page.getByRole("link", { name: "Projects" }).click();
  await page.getByRole("button", { name: "Expand project" }).click();
  await page.getByRole("treeitem", { name: /plumbing/i }).click();
}

test.describe("cost breakdown", () => {
  test("shows category totals, labor amount, and grand total on job detail", async ({
    page,
  }) => {
    await mockJobBreakdownApi(page, {
      permissions: ["jobs.view", "finance.view", "finance.manage"],
    });
    await loginAndOpenJobDetail(page);

    const breakdown = page.getByTestId("cost-breakdown");
    await expect(breakdown).toBeVisible();
    await expect(page.getByTestId("breakdown-labor-amount")).toContainText("$240.00");
    await expect(breakdown.getByText("Materials")).toBeVisible();
    await expect(breakdown.getByText("$150.00")).toBeVisible();
    await expect(page.getByTestId("breakdown-grand-total")).toContainText("$390.00");
  });

  test("shows the hours-visible unrated badge", async ({ page }) => {
    await mockJobBreakdownApi(page, {
      permissions: ["jobs.view", "finance.view", "finance.manage"],
    });
    await loginAndOpenJobDetail(page);

    await expect(page.getByTestId("breakdown-unrated-badge")).toHaveText(
      "12.5 hrs unrated"
    );
  });

  test("discloses unburdened labor in the info popover", async ({ page }) => {
    await mockJobBreakdownApi(page, {
      permissions: ["jobs.view", "finance.view", "finance.manage"],
    });
    await loginAndOpenJobDetail(page);

    await page.getByRole("button", { name: "About labor cost" }).click();

    await expect(page.getByText("Unburdened labor")).toBeVisible();
    await expect(
      page.getByText("Wage cost only — excludes payroll tax, insurance, overhead.")
    ).toBeVisible();
  });

  test("shows Tracked at job level on a trade scope breakdown", async ({ page }) => {
    await mockTradeScopeBreakdownApi(page, {
      permissions: ["projects.view", "projects.edit", "finance.view", "finance.manage"],
    });

    await loginAndOpenTradeScope(page);

    await expect(page.getByText("Tracked at job level")).toBeVisible();
    await expect(page.getByTestId("breakdown-unrated-badge")).toHaveCount(0);
  });

  test("omits the Labor option from the add-cost category picker", async ({
    page,
  }) => {
    await mockJobBreakdownApi(page, {
      permissions: ["jobs.view", "finance.view", "finance.manage"],
    });
    await loginAndOpenJobDetail(page);

    await page.getByTestId("add-cost-button").click();
    await page.getByRole("combobox", { name: /category/i }).click();

    await expect(page.getByRole("option", { name: "Materials" })).toBeVisible();
    await expect(page.getByRole("option", { name: "Labor", exact: true })).toHaveCount(0);
  });
});
