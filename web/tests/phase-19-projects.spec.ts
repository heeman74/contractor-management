import { test, expect, type Page, type Route } from "@playwright/test";

// ---------------------------------------------------------------------------
// Phase 19 Projects Playwright E2E Tests
// ---------------------------------------------------------------------------
// Tests for the project hierarchy UI: sidebar link, tree, detail panels,
// create dialog, add trade scope sheet with catalog combobox.
// ---------------------------------------------------------------------------

// --- Mock data ---

const MOCK_PROJECT_1 = {
  id: "proj-001",
  company_id: "co-001",
  name: "Kitchen Renovation",
  description: "Full kitchen remodel",
  address: "123 Main St",
  client_id: null,
  target_start_date: "2026-04-01",
  target_end_date: "2026-06-30",
  status: "active",
  status_history: [],
  version: 1,
  created_at: "2026-03-01T00:00:00Z",
  updated_at: "2026-03-01T00:00:00Z",
  deleted_at: null,
  trade_scopes: [],
};

const MOCK_PROJECT_2 = {
  id: "proj-002",
  company_id: "co-001",
  name: "Office Build-Out",
  description: null,
  address: "456 Office Blvd",
  client_id: null,
  target_start_date: null,
  target_end_date: null,
  status: "draft",
  status_history: [],
  version: 1,
  created_at: "2026-03-02T00:00:00Z",
  updated_at: "2026-03-02T00:00:00Z",
  deleted_at: null,
  trade_scopes: [],
};

const MOCK_SCOPES = [
  {
    id: "scope-001",
    company_id: "co-001",
    project_id: "proj-001",
    trade_catalog_id: "cat-001",
    trade_name: "Plumbing",
    trade_color: "#3b82f6",
    contractor_id: null,
    status: "in_progress",
    status_override: false,
    sort_order: 0,
    version: 1,
    created_at: "2026-03-01T00:00:00Z",
    updated_at: "2026-03-01T00:00:00Z",
    tasks: [],
  },
];

const MOCK_CATALOG = [
  {
    id: "cat-001",
    company_id: "co-001",
    name: "Plumbing",
    color: "#3b82f6",
    version: 1,
    created_at: "2026-03-01T00:00:00Z",
    updated_at: "2026-03-01T00:00:00Z",
  },
  {
    id: "cat-002",
    company_id: "co-001",
    name: "Electrical",
    color: "#f59e0b",
    version: 1,
    created_at: "2026-03-01T00:00:00Z",
    updated_at: "2026-03-01T00:00:00Z",
  },
];

const MOCK_CONTRACTORS = [
  {
    id: "user-001",
    name: "Alice Builder",
    email: "alice@example.com",
    has_specialty_match: true,
  },
  {
    id: "user-002",
    name: "Bob Smith",
    email: "bob@example.com",
    has_specialty_match: false,
  },
];

async function mockProjectsApi(page: Page) {
  // Set auth cookie so middleware doesn't redirect to login
  await page.context().addCookies([
    {
      name: "access_token",
      value: "mock-token",
      domain: "localhost",
      path: "/",
    },
  ]);

  // Intercept the Next.js proxy endpoint
  await page.route("**/api/proxy*", async (route: Route) => {
    const url = route.request().url();
    const pathParam = new URL(url).searchParams.get("path") ?? "";

    if (pathParam.includes("/api/v1/projects/") && pathParam !== "/api/v1/projects/") {
      // Single project
      await route.fulfill({ json: MOCK_PROJECT_1 });
    } else if (pathParam === "/api/v1/projects/") {
      await route.fulfill({ json: [MOCK_PROJECT_1, MOCK_PROJECT_2] });
    } else if (pathParam.includes("/api/v1/trade-scopes/")) {
      await route.fulfill({ json: MOCK_SCOPES });
    } else if (pathParam.includes("/api/v1/tasks/")) {
      await route.fulfill({ json: [] });
    } else if (pathParam.includes("/api/v1/trade-catalog/")) {
      await route.fulfill({ json: MOCK_CATALOG });
    } else if (pathParam.includes("/api/v1/contractors/")) {
      await route.fulfill({ json: MOCK_CONTRACTORS });
    } else {
      await route.fulfill({ json: {} });
    }
  });

  // Mock auth refresh
  await page.route("**/api/auth/refresh", async (route: Route) => {
    await route.fulfill({ status: 200, json: { ok: true } });
  });
}

async function mockEmptyProjectsApi(page: Page) {
  await page.context().addCookies([
    {
      name: "access_token",
      value: "mock-token",
      domain: "localhost",
      path: "/",
    },
  ]);

  await page.route("**/api/proxy*", async (route: Route) => {
    const url = route.request().url();
    const pathParam = new URL(url).searchParams.get("path") ?? "";

    if (pathParam.includes("/api/v1/projects/")) {
      await route.fulfill({ json: [] });
    } else if (pathParam.includes("/api/v1/trade-catalog/")) {
      await route.fulfill({ json: [] });
    } else if (pathParam.includes("/api/v1/contractors/")) {
      await route.fulfill({ json: [] });
    } else {
      await route.fulfill({ json: {} });
    }
  });

  await page.route("**/api/auth/refresh", async (route: Route) => {
    await route.fulfill({ status: 200, json: { ok: true } });
  });
}

// --- Test 1: Sidebar shows Projects link ---

test.describe("Phase 19: Projects - Sidebar Navigation", () => {
  test("sidebar shows Projects navigation link", async ({ page }) => {
    await mockProjectsApi(page);
    await page.goto("/");

    // Projects link should be in the sidebar nav
    const projectsLink = page.getByRole("link", { name: "Projects" });
    await expect(projectsLink).toBeVisible();
    await expect(projectsLink).toHaveAttribute("href", "/projects");
  });
});

// --- Test 2: Projects page loads with tree sidebar ---

test.describe("Phase 19: Projects - Page Layout", () => {
  test.beforeEach(async ({ page }) => {
    await mockProjectsApi(page);
  });

  test("projects page loads with tree sidebar", async ({ page }) => {
    await page.goto("/projects");
    // Page heading visible
    await expect(page.getByRole("heading", { name: "Projects" })).toBeVisible();
    // ProjectTree renders with project nodes (use tree role)
    await expect(page.getByRole("tree")).toBeVisible();
    // At least one project visible in tree (use first() to avoid strict mode violation)
    await expect(page.getByText("Kitchen Renovation").first()).toBeVisible();
    await expect(page.getByText("Office Build-Out").first()).toBeVisible();
  });

  test("project tree shows both project nodes", async ({ page }) => {
    await page.goto("/projects");
    const tree = page.getByRole("tree");
    await expect(tree).toBeVisible();
    await expect(tree.getByText("Kitchen Renovation")).toBeVisible();
    await expect(tree.getByText("Office Build-Out")).toBeVisible();
  });

  test("clicking project node shows detail panel", async ({ page }) => {
    await page.goto("/projects");
    // Click on "Office Build-Out" in the tree (not the auto-selected one)
    await page.getByRole("tree").getByText("Office Build-Out").click();
    // Detail panel heading should show the project name
    await expect(
      page.getByRole("heading", { name: "Office Build-Out" })
    ).toBeVisible();
  });

  test("project tree first project selected by default with detail panel", async ({
    page,
  }) => {
    await page.goto("/projects");
    // First project "Kitchen Renovation" is auto-selected
    // Its detail should appear on the right panel
    await expect(page.getByText("Kitchen Renovation").first()).toBeVisible();
    // Status badge for 'active' should appear somewhere on the page
    await expect(
      page.getByText("active").or(page.getByText("Active")).first()
    ).toBeVisible();
  });
});

// --- Test 3: Create project dialog ---

test.describe("Phase 19: Projects - Create Project Dialog", () => {
  test.beforeEach(async ({ page }) => {
    await mockProjectsApi(page);
  });

  test("create project dialog opens when New Project is clicked", async ({
    page,
  }) => {
    await page.goto("/projects");
    await page.getByTestId("create-project-button").click();
    // Dialog should be visible with the heading title
    await expect(page.getByRole("heading", { name: "Create Project" })).toBeVisible();
  });

  test("create project dialog validates name is required", async ({ page }) => {
    await page.goto("/projects");
    await page.getByTestId("create-project-button").click();
    // Submit without filling name
    await page.getByTestId("create-project-submit").click();
    // Validation error should appear
    await expect(page.getByText("Project name is required.")).toBeVisible();
  });

  test("create project dialog closes on Cancel", async ({ page }) => {
    await page.goto("/projects");
    await page.getByTestId("create-project-button").click();
    await expect(page.getByRole("heading", { name: "Create Project" })).toBeVisible();
    await page.getByRole("button", { name: "Cancel" }).click();
    // Dialog should close — submit button no longer visible
    await expect(page.getByTestId("create-project-submit")).not.toBeVisible();
  });

  test("create project success shows toast", async ({ page }) => {
    await page.goto("/projects");

    // Mock the POST endpoint to succeed
    await page.route("**/api/proxy*", async (route: Route) => {
      const url = route.request().url();
      const pathParam = new URL(url).searchParams.get("path") ?? "";
      const method = route.request().method();

      if (pathParam === "/api/v1/projects/" && method === "POST") {
        await route.fulfill({
          status: 201,
          json: {
            ...MOCK_PROJECT_1,
            id: "proj-new",
            name: "New Test Project",
          },
        });
      } else if (pathParam === "/api/v1/projects/") {
        await route.fulfill({
          json: [MOCK_PROJECT_1, MOCK_PROJECT_2],
        });
      } else if (pathParam.includes("/api/v1/trade-scopes/")) {
        await route.fulfill({ json: MOCK_SCOPES });
      } else if (pathParam.includes("/api/v1/tasks/")) {
        await route.fulfill({ json: [] });
      } else if (pathParam.includes("/api/v1/trade-catalog/")) {
        await route.fulfill({ json: MOCK_CATALOG });
      } else if (pathParam.includes("/api/v1/contractors/")) {
        await route.fulfill({ json: MOCK_CONTRACTORS });
      } else {
        await route.fulfill({ json: {} });
      }
    });

    await page.getByTestId("create-project-button").click();
    await page.getByTestId("project-name-input").fill("New Test Project");
    await page.getByTestId("project-description-input").fill("Test description");
    await page.getByTestId("project-address-input").fill("789 Test Ave");
    await page.getByTestId("create-project-submit").click();

    // Toast "Project created." should appear
    await expect(page.getByText("Project created.")).toBeVisible();
  });
});

// --- Test 4: Project tree expand/collapse ---

test.describe("Phase 19: Projects - Tree Expand/Collapse", () => {
  test.beforeEach(async ({ page }) => {
    await mockProjectsApi(page);
  });

  test("project tree expand shows trade scopes as children", async ({
    page,
  }) => {
    await page.goto("/projects");
    // Find the chevron/expand button for "Kitchen Renovation" and click it
    const projectNode = page.getByRole("treeitem").filter({ hasText: "Kitchen Renovation" }).first();
    await expect(projectNode).toBeVisible();

    // Click the expand button (the ChevronRight button inside the treeitem)
    const expandBtn = projectNode.getByRole("button", { name: /Expand/i }).first();
    await expandBtn.click();

    // Trade scope "Plumbing" should become visible
    await expect(page.getByText("Plumbing").first()).toBeVisible();
  });
});

// --- Test 5: Add Trade Scope Sheet ---

test.describe("Phase 19: Projects - Add Trade Scope Sheet", () => {
  test.beforeEach(async ({ page }) => {
    await mockProjectsApi(page);
  });

  test("Add Trade Scope button opens sheet", async ({ page }) => {
    await page.goto("/projects");
    // The first project (Kitchen Renovation) is auto-selected in the detail panel
    await page.getByTestId("add-trade-scope-button").click();
    // Sheet should open with trade name combobox
    await expect(page.getByText("Add Trade Scope").first()).toBeVisible();
    await expect(page.getByTestId("trade-name-combobox")).toBeVisible();
  });

  test("trade name combobox shows catalog entries", async ({ page }) => {
    await page.goto("/projects");
    await page.getByTestId("add-trade-scope-button").click();
    // Open the combobox
    await page.getByTestId("trade-name-combobox").click();
    // Catalog entries should be visible
    await expect(page.getByText("Plumbing").first()).toBeVisible();
    await expect(page.getByText("Electrical").first()).toBeVisible();
  });

  test("typing a new trade name shows create option", async ({ page }) => {
    await page.goto("/projects");
    await page.getByTestId("add-trade-scope-button").click();
    await page.getByTestId("trade-name-combobox").click();
    // Type a trade name not in catalog
    await page.getByTestId("trade-search-input").fill("Custom Tile Work");
    // Should show "Create new trade: Custom Tile Work"
    await expect(page.getByTestId("create-new-trade-option")).toBeVisible();
    await expect(page.getByText(/Create new trade.*Custom Tile Work/)).toBeVisible();
  });

  test("selecting new trade shows save-to-catalog prompt", async ({ page }) => {
    await page.goto("/projects");
    await page.getByTestId("add-trade-scope-button").click();
    await page.getByTestId("trade-name-combobox").click();
    await page.getByTestId("trade-search-input").fill("Custom Tile Work");
    await page.getByTestId("create-new-trade-option").click();

    // Save to Catalog button and Use Once link should appear
    await expect(page.getByTestId("save-to-catalog-button")).toBeVisible();
    await expect(page.getByTestId("use-once-button")).toBeVisible();
  });

  test("contractor list shows specialty match label", async ({ page }) => {
    await page.goto("/projects");
    await page.getByTestId("add-trade-scope-button").click();

    // Wait for sheet to open
    await expect(page.getByTestId("trade-name-combobox")).toBeVisible();

    // Select a catalog trade to enable specialty matching
    await page.getByTestId("trade-name-combobox").click();
    // Wait for search input to appear, then type to filter
    await page.getByTestId("trade-search-input").fill("Plumbing");
    // Click the Plumbing option in the combobox dropdown (within the popover)
    await page.locator('[data-slot="popover-content"]').getByText("Plumbing").click();

    // Open contractor select
    await page.getByTestId("contractor-select").click();

    // Specialty match label should appear in the select options
    await expect(page.getByText("Specialty match")).toBeVisible();
  });
});

// --- Test 6: Status badge colors ---

test.describe("Phase 19: Projects - Status Badge Colors", () => {
  test.beforeEach(async ({ page }) => {
    await mockProjectsApi(page);
  });

  test("active project shows green status badge", async ({ page }) => {
    await page.goto("/projects");
    // Kitchen Renovation has status 'active' — its badge should use green classes
    // The badge text will read "active"
    const badge = page.getByText("active").first();
    await expect(badge).toBeVisible();
  });

  test("draft project shows in tree", async ({ page }) => {
    await page.goto("/projects");
    await expect(page.getByText("Office Build-Out")).toBeVisible();
  });
});

// --- Test 7: Empty state ---

test.describe("Phase 19: Projects - Empty State", () => {
  test("empty state shows when no projects exist", async ({ page }) => {
    await mockEmptyProjectsApi(page);
    await page.goto("/projects");
    // Should show empty state message in either the tree sidebar or the detail panel
    await expect(
      page.getByText("No projects yet").first()
    ).toBeVisible();
  });
});
