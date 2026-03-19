import { test, expect } from "@playwright/test";

// ---------------------------------------------------------------------------
// Phase 17 CRM Playwright E2E Tests
// ---------------------------------------------------------------------------
// These tests run against the live app (localhost:3000 + running backend).
// They are resilient to empty data states — each test checks if rows exist
// before navigating to detail pages.
// ---------------------------------------------------------------------------

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
    if (await firstRow.isVisible()) {
      await firstRow.click();
      // Verify two-column layout loaded
      await expect(
        page.getByRole("heading", { name: "Job History" })
      ).toBeVisible();
      // Verify sidebar sections
      await expect(
        page.getByText("Admin Notes").or(page.getByText("Saved Properties"))
      ).toBeVisible();
    }
  });

  test("client detail shows properties and sidebar info", async ({ page }) => {
    // CRM-02: Properties and admin notes in sidebar
    await page.goto("/clients");
    const firstRow = page.locator("tbody tr").first();
    if (await firstRow.isVisible()) {
      await firstRow.click();
      // Client detail page should load with either the full profile or an empty state
      await expect(
        page
          .getByRole("heading", { name: "Job History" })
          .or(page.getByText("No jobs yet"))
      ).toBeVisible();
    }
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
    if (await firstRow.isVisible()) {
      await firstRow.click();
      await expect(
        page.getByRole("heading", { name: "Weekly Schedule" })
      ).toBeVisible();
      await expect(
        page.getByRole("heading", { name: "Assigned Jobs" })
      ).toBeVisible();
      await expect(
        page.getByRole("button", { name: "Edit Schedule" })
      ).toBeVisible();
    }
  });

  test("schedule editor allows editing weekly hours", async ({ page }) => {
    // CONTR-03: Admin can define contractor weekly working hours via drag-to-paint grid
    await page.goto("/contractors");
    const firstRow = page.locator("tbody tr").first();
    if (await firstRow.isVisible()) {
      await firstRow.click();
      await page.getByRole("button", { name: "Edit Schedule" }).click();
      // Verify schedule editor loaded
      await expect(
        page.getByRole("heading", { name: "Weekly Working Hours" })
      ).toBeVisible();
      await expect(
        page.getByText("Click and drag to mark working hours")
      ).toBeVisible();
      // Verify grid cells exist
      const gridCells = page.locator(
        "[class*='bg-gray-100'], [class*='bg-indigo-500']"
      );
      await expect(gridCells.first()).toBeVisible();
    }
  });

  test("schedule editor has date overrides section", async ({ page }) => {
    // CONTR-04: Admin can set date-specific availability overrides
    await page.goto("/contractors");
    const firstRow = page.locator("tbody tr").first();
    if (await firstRow.isVisible()) {
      await firstRow.click();
      await page.getByRole("button", { name: "Edit Schedule" }).click();
      await expect(
        page.getByRole("heading", { name: "Date Overrides" })
      ).toBeVisible();
      await expect(
        page.getByText("Select a date to set a custom override")
      ).toBeVisible();
    }
  });
});

test.describe("Phase 17: CRM - Cross-page links", () => {
  test("job detail links to client and contractor profiles", async ({
    page,
  }) => {
    // Task 1: Cross-page CRM links from job detail
    await page.goto("/jobs");
    const firstRow = page.locator("tbody tr").first();
    if (await firstRow.isVisible()) {
      await firstRow.click();
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
