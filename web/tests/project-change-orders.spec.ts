import { test, expect, type Page, type Route } from "@playwright/test";

// E2E: the project detail's Change Orders section lists a project's change
// orders (from GET /quotes/change-orders) with a running approved total.

const PROJECT = {
  id: "proj-1",
  company_id: "co-1",
  name: "Kitchen Reno",
  description: null,
  address: null,
  client_id: null,
  target_start_date: null,
  target_end_date: null,
  status: "active",
  status_history: [],
  version: 1,
  created_at: "2026-07-30T00:00:00Z",
  updated_at: "2026-07-30T00:00:00Z",
  deleted_at: null,
  trade_scopes: [],
};

const CHANGE_ORDER = {
  id: "co-1",
  company_id: "co-1",
  job_id: null,
  quote_kind: "change_order",
  co_number: 1,
  change_reason: "Rotted subfloor found",
  schedule_impact_days: 3,
  project_id: "proj-1",
  status: "approved",
  revision_number: 1,
  tax_rate: "0",
  discount_type: null,
  discount_value: "0",
  expiry_date: null,
  sent_at: null,
  viewed_at: null,
  approved_at: "2026-07-30T00:00:00Z",
  declined_at: null,
  decline_reason: null,
  decline_detail: null,
  admin_notes: null,
  line_items: [],
  subtotal: "840.00",
  discount_amount: "0",
  tax_amount: "0",
  total: "840.00",
  version: 1,
  created_at: "2026-07-30T00:00:00Z",
  updated_at: "2026-07-30T00:00:00Z",
};

async function mockApi(page: Page) {
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);
  await page.route("**/api/auth/login", async (route: Route) =>
    route.fulfill({
      json: {
        user_id: "u1",
        company_id: "co-1",
        email: "sarah@ace.com",
        display_name: "Sarah",
        company_name: "Ace",
        roles: ["admin"],
      },
    })
  );
  await page.route("**/api/proxy**", async (route: Route) => {
    const path = new URL(route.request().url()).searchParams.get("path") ?? "";
    if (path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: ["projects.view"] } });
    if (path.includes("/quotes/change-orders")) return route.fulfill({ json: [CHANGE_ORDER] });
    if (path.endsWith("/projects/")) return route.fulfill({ json: [PROJECT] });
    return route.fulfill({ json: [] });
  });
}

test("shows the project's change orders with an approved running total", async ({ page }) => {
  await mockApi(page);
  await page.goto("/projects");

  await expect(page.getByRole("heading", { name: "Kitchen Reno" })).toBeVisible();
  await expect(page.getByText("Change Orders (1)")).toBeVisible();
  await expect(page.getByText("CO-1 — Rotted subfloor found")).toBeVisible();
  // Running approved total: $840.00 + 3 days.
  await expect(page.getByText("Approved: $840.00 · +3d")).toBeVisible();
});
