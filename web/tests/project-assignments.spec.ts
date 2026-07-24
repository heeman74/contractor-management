import { test, expect, type Page, type Route } from "@playwright/test";

// E2E (sub-feature A): assign a PM/contractor to a project from the project detail.
// Follows the repo convention — mock /api/proxy, no live backend.

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
  created_at: "2026-07-23T00:00:00Z",
  updated_at: "2026-07-23T00:00:00Z",
  deleted_at: null,
  trade_scopes: [],
};

const USERS = [
  { id: "u1", email: "sarah@ace.com", first_name: "Sarah", last_name: "Mitchell", phone: null, roles: ["admin"] },
  { id: "u2", email: "john@ace.com", first_name: "John", last_name: "Cooper", phone: null, roles: ["contractor"] },
];

async function mockApi(page: Page, captured: { body?: unknown }) {
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);

  // Login route (not /api/proxy) — the app dispatches setAuthUser from this
  // response, which is what flips isAuthenticated on so usePermissions loads.
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

  // Stateful assignments list — starts empty, gains the created assignment.
  const assignments: Array<Record<string, unknown>> = [];

  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: ["projects.view", "projects.edit", "users.view"] } });
    if (method === "GET" && path.endsWith("/projects/"))
      return route.fulfill({ json: [PROJECT] });
    if (method === "GET" && path.includes("/trade-scopes"))
      return route.fulfill({ json: [] });
    if (method === "GET" && path.includes("/users"))
      return route.fulfill({ json: USERS });
    if (method === "GET" && path.includes(`/projects/${PROJECT.id}/assignments`))
      return route.fulfill({ json: assignments });
    if (method === "POST" && path.includes(`/projects/${PROJECT.id}/assignments`)) {
      captured.body = req.postDataJSON();
      const created = {
        id: "a-new",
        company_id: "co-1",
        project_id: PROJECT.id,
        user_id: (captured.body as { user_id: string }).user_id,
        role: (captured.body as { role: string }).role,
        assigned_at: "2026-07-23T00:00:00Z",
        user_name: "Sarah Mitchell",
        project_name: PROJECT.name,
        version: 1,
        created_at: "2026-07-23T00:00:00Z",
        updated_at: "2026-07-23T00:00:00Z",
      };
      assignments.push(created);
      return route.fulfill({ status: 201, json: created });
    }
    return route.fulfill({ status: 404, json: { detail: `unmatched ${method} ${path}` } });
  });
}

test("assigns a project manager to a project", async ({ page }) => {
  const captured: { body?: unknown } = {};
  await mockApi(page, captured);

  // Log in through the UI so Redux auth + permissions are populated, then
  // navigate to Projects via the sidebar (SPA nav preserves that state; a hard
  // goto would reset isAuthenticated and hide the permission-gated form).
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
  await page.getByRole("link", { name: "Projects" }).click();

  // The detail auto-selects the first project → the Team section renders.
  await expect(page.getByRole("heading", { name: /Team/ })).toBeVisible();
  await expect(page.getByText("No one assigned yet.")).toBeVisible();

  // Pick role = Project Manager, user = Sarah Mitchell, Assign.
  await page.getByRole("combobox", { name: /role/i }).click();
  await page.getByRole("option", { name: "Project Manager" }).click();
  await page.getByRole("combobox", { name: /user/i }).click();
  await page.getByRole("option", { name: "Sarah Mitchell" }).click();
  await page.getByRole("button", { name: /^assign$/i }).click();

  // Correct payload sent...
  await expect.poll(() => captured.body).toEqual({ user_id: "u1", role: "project_manager" });
  // ...and the new assignment shows in the Team list with its role badge.
  const row = page.locator("li").filter({ hasText: "Project Manager" });
  await expect(row).toContainText("Sarah Mitchell");
});
