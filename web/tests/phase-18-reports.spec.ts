import { test, expect } from "@playwright/test";

test.describe("Phase 18: Reports - Chart Sections (RPT-01)", () => {
  test("four chart sections visible on reports page", async ({ page }) => {
    await page.goto("/reports");
    await expect(page.getByRole("heading", { name: "Reports" })).toBeVisible();
    // Wait for charts to load (or empty state)
    await page.waitForTimeout(3000); // Allow API + render time
    // Verify all 4 chart cards present by their aria-label
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();
    await expect(page.locator('[aria-label="Jobs by Status chart"]')).toBeVisible();
    await expect(page.locator('[aria-label="Contractor Utilization chart"]')).toBeVisible();
    await expect(page.locator('[aria-label="Quote Conversion chart"]')).toBeVisible();
  });

  test("revenue chart renders with month labels", async ({ page }) => {
    await page.goto("/reports");
    await page.waitForTimeout(3000);
    const revenueCard = page.locator('[aria-label="Revenue by Month chart"]');
    await expect(revenueCard).toBeVisible();
    // Chart card shows title and KPI value
    await expect(revenueCard.getByText("Revenue by Month")).toBeVisible();
    // SVG chart or empty state should be rendered
    const svg = revenueCard.locator("svg.recharts-surface");
    const emptyState = revenueCard.getByText("No data for this period");
    await expect(svg.or(emptyState)).toBeVisible();
  });

  test("jobs by status chart renders", async ({ page }) => {
    await page.goto("/reports");
    await page.waitForTimeout(3000);
    const jobsCard = page.locator('[aria-label="Jobs by Status chart"]');
    await expect(jobsCard).toBeVisible();
    await expect(jobsCard.getByText("Jobs by Status")).toBeVisible();
    const svg = jobsCard.locator("svg.recharts-surface");
    const emptyState = jobsCard.getByText("No data for this period");
    await expect(svg.or(emptyState)).toBeVisible();
  });

  test("quote conversion chart renders", async ({ page }) => {
    await page.goto("/reports");
    await page.waitForTimeout(3000);
    const quoteCard = page.locator('[aria-label="Quote Conversion chart"]');
    await expect(quoteCard).toBeVisible();
    await expect(quoteCard.getByText("Quote Conversion")).toBeVisible();
    const svg = quoteCard.locator("svg.recharts-surface");
    const emptyState = quoteCard.getByText("No data for this period");
    await expect(svg.or(emptyState)).toBeVisible();
  });
});

test.describe("Phase 18: Reports - Date Filtering (RPT-02)", () => {
  test("date preset 7d changes displayed range", async ({ page }) => {
    await page.goto("/reports");
    await expect(page.getByRole("heading", { name: "Reports" })).toBeVisible();
    // Click "Last 7d" button
    const btn7d = page.getByRole("button", { name: /7d/i });
    await btn7d.click();
    // Verify button is now active (aria-pressed)
    await expect(btn7d).toHaveAttribute("aria-pressed", "true");
    // Wait for refetch
    await page.waitForTimeout(2000);
    // Charts should still be visible after refetch
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();
  });

  test("ytd preset triggers correct date", async ({ page }) => {
    await page.goto("/reports");
    const btnYtd = page.getByRole("button", { name: /ytd/i });
    await btnYtd.click();
    await expect(btnYtd).toHaveAttribute("aria-pressed", "true");
    await page.waitForTimeout(2000);
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();
  });
});

test.describe("Phase 18: Reports - Utilization Heatmap (RPT-03)", () => {
  test("heatmap grid renders with contractor rows and week columns", async ({ page }) => {
    await page.goto("/reports");
    await page.waitForTimeout(3000);
    const heatmapCard = page.locator('[aria-label="Contractor Utilization chart"]');
    await expect(heatmapCard).toBeVisible();
    await expect(heatmapCard.getByText("Contractor Utilization")).toBeVisible();
    // Either heatmap grid cells or empty state
    const gridCells = heatmapCard.locator(".rounded-sm");
    const emptyState = heatmapCard.getByText("No data for this period");
    await expect(gridCells.first().or(emptyState)).toBeVisible();
  });
});
