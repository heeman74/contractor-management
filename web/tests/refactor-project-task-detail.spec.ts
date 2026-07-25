import { test, expect, type Page, type Route } from "@playwright/test";

// Regression: the projects list endpoint does NOT embed trade_scopes/tasks, so
// the detail panel used to look them up in an always-empty array and hang on
// "Loading task…". The tree now passes the resolved scope/task object through
// selection. This drives project → scope → task and asserts the detail renders.

const PROJECT = {
  id: "p-1",
  company_id: "co-1",
  name: "Panel Replacement",
  description: null,
  address: null,
  client_id: null,
  target_start_date: null,
  target_end_date: null,
  status: "active",
  status_history: [],
  version: 1,
  created_at: "2026-07-24T00:00:00Z",
  updated_at: "2026-07-24T00:00:00Z",
  deleted_at: null,
  trade_scopes: [], // list endpoint never embeds these — that's the whole point
};

const SCOPE = {
  id: "s-1",
  company_id: "co-1",
  project_id: "p-1",
  trade_catalog_id: null,
  trade_name: "Electrical",
  trade_color: "#eab308",
  contractor_id: null,
  status: "not_started",
  status_override: false,
  sort_order: 0,
  version: 1,
  created_at: "2026-07-24T00:00:00Z",
  updated_at: "2026-07-24T00:00:00Z",
  deleted_at: null,
};

const TASK = {
  id: "t-1",
  company_id: "co-1",
  trade_scope_id: "s-1",
  title: "[Scope placeholder] Electrical rough-in",
  description: "Pull new feeders and set the 150A main panel.",
  status: "not_started",
  sort_order: 0,
  priority: "medium",
  estimated_hours: null,
  estimated_cost: null,
  due_date: null,
  start_date: null,
  zone_id: null,
  photo_required: false,
  assigned_to: null,
  materials_needed: [],
  version: 1,
  created_at: "2026-07-24T00:00:00Z",
  updated_at: "2026-07-24T00:00:00Z",
  deleted_at: null,
};

async function mockApi(page: Page) {
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);
  await page.route("**/api/auth/login", async (route: Route) =>
    route.fulfill({
      json: {
        user_id: "admin-1",
        company_id: "co-1",
        email: "sarah@ace.com",
        display_name: "Sarah Mitchell",
        company_name: "Ace",
        roles: ["admin"],
      },
    })
  );
  await page.route("**/api/proxy**", async (route: Route) => {
    const path = new URL(route.request().url()).searchParams.get("path") ?? "";
    if (path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: ["projects.view", "projects.edit"] } });
    if (path.includes("/trade-scopes")) return route.fulfill({ json: [SCOPE] });
    if (path.includes("/tasks")) return route.fulfill({ json: [TASK] });
    if (path.endsWith("/projects/")) return route.fulfill({ json: [PROJECT] });
    return route.fulfill({ json: [] });
  });
}

test("selecting a task in the tree loads its detail instead of hanging on 'Loading task…'", async ({
  page,
}) => {
  await mockApi(page);
  await page.goto("/projects");

  const tree = page.getByRole("tree");
  // Auto-selects the project; expand it to lazy-load scopes.
  await tree.getByRole("button", { name: "Expand project" }).click();
  await expect(tree.getByText("Electrical")).toBeVisible();

  // Expand the scope to lazy-load its tasks.
  await tree.getByRole("button", { name: "Expand", exact: true }).click();
  const taskNode = tree.getByText("[Scope placeholder] Electrical rough-in");
  await expect(taskNode).toBeVisible();

  // Click the task → detail panel must render the task (description is unique
  // to TaskDetail), never the stuck "Loading task…" state.
  await taskNode.click();
  await expect(
    page.getByText("Pull new feeders and set the 150A main panel.")
  ).toBeVisible();
  await expect(page.getByText("Loading task...")).toHaveCount(0);
});

test("selecting a scope in the tree loads its detail (no 'Loading scope…')", async ({
  page,
}) => {
  await mockApi(page);
  await page.goto("/projects");

  const tree = page.getByRole("tree");
  await tree.getByRole("button", { name: "Expand project" }).click();
  const scopeNode = tree.getByText("Electrical");
  await expect(scopeNode).toBeVisible();

  await scopeNode.click();
  // TradeScopeDetail lists the scope's tasks — the task title appears in the
  // detail panel, and the stuck loading state is absent.
  await expect(page.getByText("Loading scope...")).toHaveCount(0);
  await expect(
    page.getByText("[Scope placeholder] Electrical rough-in")
  ).toBeVisible();
});
