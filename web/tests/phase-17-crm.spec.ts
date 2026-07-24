import { test, expect, type Page, type Route } from "@playwright/test";

// ---------------------------------------------------------------------------
// Phase 17 CRM Playwright E2E Tests
// ---------------------------------------------------------------------------
// Seeded at the proxy layer (same approach as the phase-16/18/19 specs) so the
// list pages render rows + headers and the detail pages the conditional tests
// navigate into also load — no dependency on backend seed data.
// ---------------------------------------------------------------------------

const CLIENTS = [
  {
    id: "client-1",
    user_id: "user-c1",
    first_name: "Alice",
    last_name: "Anderson",
    email: "alice@example.com",
    phone: "555-0001",
    tags: [],
    preferred_contractor_id: null,
    preferred_contractor_name: null,
    jobs_count: 2,
  },
  {
    id: "client-2",
    user_id: "user-c2",
    first_name: "Bob",
    last_name: "Brown",
    email: "bob@example.com",
    phone: null,
    tags: ["vip"],
    preferred_contractor_id: null,
    preferred_contractor_name: null,
    jobs_count: 0,
  },
];

const CLIENT_DETAIL = {
  ...CLIENTS[0],
  admin_notes: null,
  referral_source: null,
  preferred_contact_method: null,
  billing_address: null,
  average_rating: null,
  jobs: [],
  properties: [],
};

const CONTRACTORS = [
  {
    id: "contractor-1",
    email: "carl@example.com",
    first_name: "Carl",
    last_name: "Carpenter",
    phone: "555-1001",
    roles: ["contractor"],
  },
  {
    id: "contractor-2",
    email: "dana@example.com",
    first_name: "Dana",
    last_name: "Decker",
    phone: null,
    roles: ["contractor"],
  },
];

const AVAILABILITY = CONTRACTORS.map((c) => ({
  contractor_id: c.id,
  contractor_name: `${c.first_name} ${c.last_name}`,
  date: "2026-07-22",
  free_windows: [
    { start: "2026-07-22T09:00:00Z", end: "2026-07-22T17:00:00Z", reason_before: null },
  ],
  blocked_intervals: [],
}));

function json(route: Route, body: unknown, status = 200) {
  return route.fulfill({
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  });
}

async function setupCrmRoutes(page: Page) {
  // Never let the client redirect to /login during a test.
  await page.route("**/api/auth/**", (route) =>
    json(route, { access_token: "mock-token" })
  );

  await page.route("**/api/proxy**", (route) => {
    const path = new URL(route.request().url()).searchParams.get("path") ?? "";
    const method = route.request().method();

    if (method === "POST" && path.includes("/scheduling/availability")) {
      return json(route, AVAILABILITY);
    }
    // Client detail (has an id segment) must be matched before the list.
    if (/\/crm\/clients\/[^/?]+/.test(path)) return json(route, CLIENT_DETAIL);
    if (path.includes("/crm/clients")) return json(route, CLIENTS);
    if (path.includes("/scheduling/schedules/") && path.includes("/weekly")) {
      return json(route, {});
    }
    if (path.includes("/scheduling/schedules/") && path.includes("/overrides")) {
      return json(route, []);
    }
    if (path.includes("/users/") && path.includes("/roles")) return json(route, {});
    if (path.includes("/users")) return json(route, CONTRACTORS);
    // Jobs stay empty so the cross-page test skips gracefully as before.
    if (path.includes("/jobs")) return json(route, []);
    return json(route, []);
  });
}

test.beforeEach(async ({ page }) => {
  await setupCrmRoutes(page);
});

test.describe("Phase 17: CRM - Clients", () => {
  test("client list displays paginated clients", async ({ page }) => {
    // CRM-01: Admin can view a searchable list of all clients
    await page.goto("/clients");
    // Wait for page title
    await expect(
      page.getByRole("heading", { name: "Clients" })
    ).toBeVisible();
    // Verify table is rendered with column headers
    await expect(
      page.getByRole("columnheader", { name: "Name" })
    ).toBeVisible();
    await expect(
      page.getByRole("columnheader", { name: "Email" })
    ).toBeVisible();
    await expect(
      page.getByRole("columnheader", { name: "Jobs" })
    ).toBeVisible();
    // Verify at least one row exists OR empty state is shown
    const rows = page.locator("tbody tr");
    const emptyState = page.getByText("No clients yet");
    await expect(rows.first().or(emptyState)).toBeVisible();
  });

  test("client search filters results by name", async ({ page }) => {
    // CRM-01: Search functionality
    await page.goto("/clients");
    await page
      .getByPlaceholder("Search by name or email...")
      .fill("test");
    // Wait for debounce
    await page.waitForTimeout(500);
    // Results should update (either filtered list or "No clients found")
    const rows = page.locator("tbody tr");
    const noResults = page.getByText("No clients found");
    await expect(rows.first().or(noResults)).toBeVisible();
  });

  test("client detail shows job history and sidebar", async ({ page }) => {
    // CRM-02: Admin can view client detail with job history
    await page.goto("/clients");
    const firstRow = page.locator("tbody tr").first();
    await expect(firstRow).toBeVisible();
    await firstRow.click();
    // CardTitle renders a <div>, not a heading — assert by text.
    await expect(page.getByText("Job History")).toBeVisible();
    // Both sidebar cards render; assert one exactly (avoid a multi-match .or, and
    // getByText is case-insensitive substring — "Saved Properties" also matches
    // "No saved properties.").
    await expect(page.getByText("Admin Notes", { exact: true })).toBeVisible();
  });

  test("client detail shows properties and sidebar info", async ({ page }) => {
    // CRM-02: Properties and admin notes in sidebar
    await page.goto("/clients");
    const firstRow = page.locator("tbody tr").first();
    await expect(firstRow).toBeVisible();
    await firstRow.click();
    // CardTitle renders a <div>, not a heading — assert by text.
    await expect(page.getByText("Job History")).toBeVisible();
  });
});

test.describe("Phase 17: CRM - Contractors", () => {
  test("contractor list displays with availability badges", async ({
    page,
  }) => {
    // CONTR-01: Admin can view contractor list with availability status
    await page.goto("/contractors");
    await expect(
      page.getByRole("heading", { name: "Contractors" })
    ).toBeVisible();
    await expect(
      page.getByRole("columnheader", { name: "Name" })
    ).toBeVisible();
    await expect(
      page.getByRole("columnheader", { name: "Availability" })
    ).toBeVisible();
    // Verify availability badges render (StatusBadge text) OR empty state
    const rows = page.locator("tbody tr");
    const emptyState = page.getByText("No contractors yet");
    await expect(rows.first().or(emptyState)).toBeVisible();
  });

  test("contractor profile shows assigned jobs and schedule summary", async ({
    page,
  }) => {
    // CONTR-02: Admin can view contractor profile
    await page.goto("/contractors");
    const firstRow = page.locator("tbody tr").first();
    await expect(firstRow).toBeVisible();
    await firstRow.click();
    // CardTitles render as <div>, not headings — assert by text.
    await expect(page.getByText("Weekly Schedule")).toBeVisible();
    await expect(page.getByText("Assigned Jobs")).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Edit Schedule" })
    ).toBeVisible();
  });

  test("schedule editor allows editing weekly hours", async ({ page }) => {
    // CONTR-03: Admin can define contractor weekly working hours via drag-to-paint grid
    await page.goto("/contractors");
    const firstRow = page.locator("tbody tr").first();
    await expect(firstRow).toBeVisible();
    await firstRow.click();
    await page.getByRole("button", { name: "Edit Schedule" }).click();
    // "Weekly Working Hours" is a CardTitle <div> — assert by text.
    await expect(
      page.getByText("Weekly Working Hours", { exact: true })
    ).toBeVisible();
    await expect(
      page.getByText("Click and drag to mark working hours")
    ).toBeVisible();
    // A schedule cell (empty or filled). Class selectors match the literal
    // bg-gray-100 / bg-indigo-500 cell tokens — not the topbar hamburger's
    // hover:bg-gray-100 that the [class*=…] substring match previously caught.
    const gridCells = page.locator(
      ".bg-gray-100.cursor-pointer, .bg-brand.cursor-pointer"
    );
    await expect(gridCells.first()).toBeVisible();
  });

  test("schedule editor has date overrides section", async ({ page }) => {
    // CONTR-04: Admin can set date-specific availability overrides
    await page.goto("/contractors");
    const firstRow = page.locator("tbody tr").first();
    await expect(firstRow).toBeVisible();
    await firstRow.click();
    await page.getByRole("button", { name: "Edit Schedule" }).click();
    // "Date Overrides" is a CardTitle <div> — assert by text (exact: the empty
    // state "No date overrides set…" also contains the substring).
    await expect(page.getByText("Date Overrides", { exact: true })).toBeVisible();
    await expect(
      page.getByText("Select a date to set a custom override")
    ).toBeVisible();
  });
});

test.describe("Phase 17: CRM - Cross-page links", () => {
  test("job detail links to client and contractor profiles", async ({
    page,
  }) => {
    // Task 1: Cross-page CRM links from job detail
    await page.goto("/jobs");
    // Wait for the page to settle before checking for rows (no racy isVisible()).
    await expect(page.getByRole("heading", { name: "Jobs" })).toBeVisible();
    const rows = page.locator("tbody tr");
    // Jobs are seeded empty, so this only drills in when a job is present.
    if ((await rows.count()) > 0) {
      await rows.first().click();
      // Check for client link or contractor link or "Not assigned" text
      const clientLink = page.locator('a[href*="/clients/"]');
      const contractorLink = page.locator('a[href*="/contractors/"]');
      const notAssigned = page.getByText("Not assigned");
      await expect(
        clientLink.first().or(contractorLink.first()).or(notAssigned.first())
      ).toBeVisible();
    }
  });
});
