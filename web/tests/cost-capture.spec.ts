import { test, expect, type Page, type Route } from "@playwright/test";

// E2E: gated cost-capture flow (COST-01/02/03, D-02, D-06).
// Follows the repo convention — mock /api/proxy, log in through the UI so
// Redux auth + permissions populate, then SPA-navigate to Projects (auto-selects
// the first project) and expand it to reach the trade-scope Costs section.

const PROJECT = {
  id: "proj-1",
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
  id: "scope-1",
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
  { id: "cat-1", name: "Materials", is_system: true },
  { id: "cat-2", name: "Subcontractor", is_system: true },
];

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

  // Stateful cost-entries list, scoped to the trade scope — starts empty,
  // gains the created entry after a successful POST.
  const costEntries: Array<Record<string, unknown>> = [];
  const receiptRequests: Array<{ costEntryId: string }> = [];

  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: options.permissions } });
    if (method === "GET" && path.endsWith("/projects/"))
      return route.fulfill({ json: [PROJECT] });
    if (method === "GET" && path.includes(`/projects/${PROJECT.id}/assignments`))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes(`/jobs/?project_id=${PROJECT.id}`))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes("/trade-scopes"))
      return route.fulfill({ json: [TRADE_SCOPE] });
    if (method === "GET" && path.includes("/tasks"))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes(`/projects/${PROJECT.id}/cost-entries`))
      return route.fulfill({
        json: { project_id: PROJECT.id, total: "0", entries: [] },
      });
    if (method === "GET" && path.includes("/cost-categories"))
      return route.fulfill({ json: CATEGORIES });
    if (method === "GET" && path.includes("/cost-entries") && path.includes("trade_scope_id"))
      return route.fulfill({ json: costEntries });
    if (method === "POST" && path.endsWith("/cost-entries/")) {
      captured.body = req.postDataJSON();
      const body = captured.body as {
        category_id: string;
        amount: string;
        incurred_date: string;
        trade_scope_id?: string;
        job_id?: string;
      };
      const created = {
        id: "entry-new",
        job_id: body.job_id ?? null,
        trade_scope_id: body.trade_scope_id ?? null,
        category_id: body.category_id,
        category_name: CATEGORIES.find((c) => c.id === body.category_id)?.name,
        amount: body.amount,
        incurred_date: body.incurred_date,
        vendor: null,
        note: null,
        created_at: "2026-07-25T00:00:00Z",
        updated_at: "2026-07-25T00:00:00Z",
      };
      costEntries.push(created);
      return route.fulfill({ status: 201, json: created });
    }
    if (method === "POST" && path.includes("/receipts")) {
      const costEntryId = path.match(/cost-entries\/([^/]+)\/receipts/)?.[1] ?? "";
      receiptRequests.push({ costEntryId });
      return route.fulfill({
        status: 201,
        json: {
          id: "receipt-1",
          cost_entry_id: costEntryId,
          remote_url: `/files/cost-receipts/${costEntryId}/receipt.png`,
          caption: null,
          created_at: "2026-07-25T00:00:00Z",
        },
      });
    }
    return route.fulfill({ status: 404, json: { detail: `unmatched ${method} ${path}` } });
  });

  return { receiptRequests };
}

async function loginAndOpenProjects(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
  await page.getByRole("link", { name: "Projects" }).click();
}

async function openTradeScope(page: Page) {
  await page.getByRole("button", { name: "Expand project" }).click();
  await page.getByRole("treeitem", { name: /plumbing/i }).click();
}

test("adds a cost entry with finance permissions and it appears in the list", async ({
  page,
}) => {
  const captured: { body?: unknown } = {};
  await mockApi(page, captured, {
    permissions: ["projects.view", "projects.edit", "finance.view", "finance.manage"],
  });

  await loginAndOpenProjects(page);
  await openTradeScope(page);

  await expect(page.getByText("Costs", { exact: true })).toBeVisible();
  await page.getByTestId("add-cost-button").click();

  await expect(page.getByRole("heading", { name: "Add Cost" })).toBeVisible();
  await page.getByLabel(/amount/i).fill("245.50");
  await page.getByRole("combobox", { name: /category/i }).click();
  await page.getByRole("option", { name: "Materials" }).click();
  await page.getByRole("button", { name: /^add cost$/i }).click();

  await expect.poll(() => captured.body).toMatchObject({
    trade_scope_id: TRADE_SCOPE.id,
    category_id: "cat-1",
    amount: "245.50",
  });

  await expect(
    page.getByRole("main").getByText("Materials", { exact: true })
  ).toBeVisible();
  await expect(page.getByText("$245.50", { exact: true })).toBeVisible();
});

test("attaches a receipt when adding a cost entry", async ({ page }) => {
  const captured: { body?: unknown } = {};
  const { receiptRequests } = await mockApi(page, captured, {
    permissions: ["projects.view", "projects.edit", "finance.view", "finance.manage"],
  });

  await loginAndOpenProjects(page);
  await openTradeScope(page);

  await page.getByTestId("add-cost-button").click();
  await page.getByLabel(/amount/i).fill("99.99");
  await page.getByRole("combobox", { name: /category/i }).click();
  await page.getByRole("option", { name: "Subcontractor" }).click();
  await page.locator("#cost-receipt").setInputFiles({
    name: "receipt.png",
    mimeType: "image/png",
    buffer: Buffer.from("fake-receipt-bytes"),
  });
  await page.getByRole("button", { name: /^add cost$/i }).click();

  await expect.poll(() => receiptRequests.length).toBeGreaterThan(0);
  expect(receiptRequests[0].costEntryId).toBe("entry-new");
});

test("hides the Costs section entirely without finance.view", async ({ page }) => {
  const captured: { body?: unknown } = {};
  await mockApi(page, captured, {
    permissions: ["projects.view", "projects.edit"],
  });

  await loginAndOpenProjects(page);

  // Project detail auto-selected — no ProjectCostsCard "Costs" heading at all.
  await expect(page.getByText("Costs", { exact: true })).not.toBeVisible();

  await openTradeScope(page);

  // Trade-scope detail — same gate, no Costs heading and no Add cost control.
  await expect(page.getByText("Costs", { exact: true })).not.toBeVisible();
  await expect(page.getByTestId("add-cost-button")).not.toBeVisible();
});
