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
