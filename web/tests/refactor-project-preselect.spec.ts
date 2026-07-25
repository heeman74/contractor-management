import { test, expect, type Page, type Route } from "@playwright/test";

// Regression: the AI-intake / interview flows redirect to /projects?project=<id>
// (there is NO standalone /projects/[id] route — /projects is a master-detail
// page). This verifies the ?project= param opens that project pre-selected in
// the detail panel, and documents that the bare /projects/[id] URL 404s.

function project(id: string, name: string) {
  return {
    id,
    company_id: "co-1",
    name,
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
    trade_scopes: [],
  };
}

// Project A is first in the list (what auto-select would pick); B is the target.
const PROJECT_A = project("11111111-1111-1111-1111-111111111111", "Downtown Remodel");
const PROJECT_B = project("22222222-2222-2222-2222-222222222222", "Warehouse Buildout");

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
    if (path.endsWith("/projects/")) return route.fulfill({ json: [PROJECT_A, PROJECT_B] });
    return route.fulfill({ json: [] });
  });
}

test.describe("projects ?project= pre-selection", () => {
  test("opens the project named in the query param, not the first one", async ({ page }) => {
    await mockApi(page);
    await page.goto(`/projects?project=${PROJECT_B.id}`);

    // Detail panel header (<h2>) reflects the pre-selected project.
    await expect(
      page.getByRole("heading", { level: 2, name: "Warehouse Buildout" })
    ).toBeVisible();
    // It must NOT have fallen back to auto-selecting the first project.
    await expect(
      page.getByRole("heading", { level: 2, name: "Downtown Remodel" })
    ).toHaveCount(0);
  });

  test("without the param it auto-selects the first project (unchanged behavior)", async ({ page }) => {
    await mockApi(page);
    await page.goto(`/projects`);
    await expect(
      page.getByRole("heading", { level: 2, name: "Downtown Remodel" })
    ).toBeVisible();
  });

  test("the bare /projects/[id] URL has no route and 404s (by design)", async ({ page }) => {
    await mockApi(page);
    const response = await page.goto(`/projects/${PROJECT_B.id}`);
    expect(response?.status()).toBe(404);
  });
});
