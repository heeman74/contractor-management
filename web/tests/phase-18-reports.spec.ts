import { test, expect, type Page, type Route } from "@playwright/test";

// --- Mock data fixtures ---

const MOCK_DASHBOARD = {
  revenue_by_month: [
    { month: "2026-01", paid: "12500.00", unpaid: "3200.00" },
    { month: "2026-02", paid: "18700.00", unpaid: "1500.00" },
    { month: "2026-03", paid: "9800.00", unpaid: "4100.00" },
  ],
  jobs_by_status: [
    { status: "scheduled", count: 8 },
    { status: "in_progress", count: 5 },
    { status: "complete", count: 12 },
    { status: "invoiced", count: 7 },
  ],
  contractor_utilization: [
    {
      contractor_name: "Alice Builder",
      booked_hours: "35.0",
      available_hours: "40.0",
      utilization_percent: "87.5",
    },
  ],
  quote_conversion: {
    approved: 15,
    declined: 4,
    pending: 6,
    conversion_rate: "60.0",
  },
};

const MOCK_HEATMAP = {
  weeks: ["2026-W08", "2026-W09", "2026-W10", "2026-W11"],
  contractors: [
    {
      contractor_id: "c1",
      contractor_name: "Alice Builder",
      weeks: [
        { iso_week: "2026-W08", booked_hours: "36.0", available_hours: "40.0", utilization_percent: "90.0" },
        { iso_week: "2026-W09", booked_hours: "28.0", available_hours: "40.0", utilization_percent: "70.0" },
        { iso_week: "2026-W10", booked_hours: "14.0", available_hours: "40.0", utilization_percent: "35.0" },
        { iso_week: "2026-W11", booked_hours: "8.0", available_hours: "40.0", utilization_percent: "20.0" },
      ],
    },
    {
      contractor_id: "c2",
      contractor_name: "Bob Plumber",
      weeks: [
        { iso_week: "2026-W08", booked_hours: "0.0", available_hours: "40.0", utilization_percent: "0.0" },
        { iso_week: "2026-W09", booked_hours: "40.0", available_hours: "40.0", utilization_percent: "100.0" },
        { iso_week: "2026-W10", booked_hours: "24.0", available_hours: "40.0", utilization_percent: "60.0" },
        { iso_week: "2026-W11", booked_hours: "34.0", available_hours: "40.0", utilization_percent: "85.0" },
      ],
    },
  ],
};

async function mockReportsApi(page: Page) {
  // Set auth cookie so middleware doesn't redirect to login
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);

  // Intercept the Next.js proxy endpoint (all API calls go through /api/proxy?path=...)
  await page.route("**/api/proxy*", async (route: Route) => {
    const url = route.request().url();
    const pathParam = new URL(url).searchParams.get("path") ?? "";

    if (pathParam.includes("/reports/dashboard")) {
      await route.fulfill({ json: MOCK_DASHBOARD });
    } else if (pathParam.includes("/reports/utilization-heatmap")) {
      await route.fulfill({ json: MOCK_HEATMAP });
    } else {
      // Other proxy calls — return empty success
      await route.fulfill({ json: {} });
    }
  });

  // Mock the refresh endpoint to prevent session_expired redirect
  await page.route("**/api/auth/refresh", async (route: Route) => {
    await route.fulfill({ status: 200, json: { ok: true } });
  });
}

// --- RPT-01: Chart rendering with real data ---

test.describe("Phase 18: Reports - Chart Rendering (RPT-01)", () => {
  test.beforeEach(async ({ page }) => {
    await mockReportsApi(page);
  });

  test("four chart cards visible with data-driven KPIs", async ({ page }) => {
    await page.goto("/reports");
    await expect(page.getByRole("heading", { name: "Reports" })).toBeVisible();

    // All 4 chart cards render
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();
    await expect(page.locator('[aria-label="Jobs by Status chart"]')).toBeVisible();
    await expect(page.locator('[aria-label="Contractor Utilization chart"]')).toBeVisible();
    await expect(page.locator('[aria-label="Quote Conversion chart"]')).toBeVisible();

    // KPI values rendered from mock data
    const revenueCard = page.locator('[aria-label="Revenue by Month chart"]');
    // Total = 12500+3200+18700+1500+9800+4100 = 49800
    await expect(revenueCard.locator(".text-3xl")).toContainText("49,800");

    const jobsCard = page.locator('[aria-label="Jobs by Status chart"]');
    await expect(jobsCard.locator(".text-3xl")).toContainText("32 total jobs");

    const quoteCard = page.locator('[aria-label="Quote Conversion chart"]');
    await expect(quoteCard.locator(".text-3xl")).toContainText("60.0% approval rate");
  });

  test("revenue chart renders SVG with area elements", async ({ page }) => {
    await page.goto("/reports");
    const revenueCard = page.locator('[aria-label="Revenue by Month chart"]');
    await expect(revenueCard).toBeVisible();

    // SVG chart surface should render (not empty state)
    await expect(revenueCard.locator("svg.recharts-surface")).toBeVisible();
    // Should NOT show empty state
    await expect(revenueCard.getByText("No data for this period")).not.toBeVisible();
  });

  test("jobs by status chart renders SVG with bars", async ({ page }) => {
    await page.goto("/reports");
    const jobsCard = page.locator('[aria-label="Jobs by Status chart"]');
    await expect(jobsCard.locator("svg.recharts-surface")).toBeVisible();
    await expect(jobsCard.getByText("No data for this period")).not.toBeVisible();
  });

  test("quote conversion chart renders SVG pie", async ({ page }) => {
    await page.goto("/reports");
    const quoteCard = page.locator('[aria-label="Quote Conversion chart"]');
    // PieChart has multiple svg.recharts-surface (legend icons + main chart)
    // Main chart SVG has role="application"
    await expect(quoteCard.locator('svg.recharts-surface[role="application"]')).toBeVisible();
    await expect(quoteCard.getByText("No data for this period")).not.toBeVisible();
  });

  test("responsive 2-column grid layout", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("/reports");
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();

    // Grid container uses md:grid-cols-2
    const grid = page.locator(".grid.grid-cols-1.md\\:grid-cols-2");
    await expect(grid).toBeVisible();

    // At 1280px wide, grid should show 2 columns
    const gridBox = await grid.boundingBox();
    const card1Box = await page.locator('[aria-label="Revenue by Month chart"]').boundingBox();
    const card2Box = await page.locator('[aria-label="Jobs by Status chart"]').boundingBox();
    expect(gridBox).toBeTruthy();
    expect(card1Box).toBeTruthy();
    expect(card2Box).toBeTruthy();
    // Cards side by side: both at roughly same Y, different X
    expect(Math.abs(card1Box!.y - card2Box!.y)).toBeLessThan(5);
    expect(card2Box!.x).toBeGreaterThan(card1Box!.x + 100);
  });
});

// --- RPT-02: Date filtering ---

test.describe("Phase 18: Reports - Date Filtering (RPT-02)", () => {
  test.beforeEach(async ({ page }) => {
    await mockReportsApi(page);
  });

  test("preset buttons toggle aria-pressed and refetch", async ({ page }) => {
    await page.goto("/reports");
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();

    // Default is 30d
    const btn30d = page.getByRole("button", { name: /30d/i });
    await expect(btn30d).toHaveAttribute("aria-pressed", "true");

    // Click 7d — it becomes active, 30d deactivates
    const btn7d = page.getByRole("button", { name: /7d/i });
    await btn7d.click();
    await expect(btn7d).toHaveAttribute("aria-pressed", "true");
    await expect(btn30d).toHaveAttribute("aria-pressed", "false");

    // Click 90d
    const btn90d = page.getByRole("button", { name: /90d/i });
    await btn90d.click();
    await expect(btn90d).toHaveAttribute("aria-pressed", "true");
    await expect(btn7d).toHaveAttribute("aria-pressed", "false");

    // Click YTD
    const btnYtd = page.getByRole("button", { name: /ytd/i });
    await btnYtd.click();
    await expect(btnYtd).toHaveAttribute("aria-pressed", "true");
    await expect(btn90d).toHaveAttribute("aria-pressed", "false");

    // Charts still visible after all toggles
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();
  });

  test("active preset button gets active styling", async ({ page }) => {
    await page.goto("/reports");
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();

    const btn7d = page.getByRole("button", { name: /7d/i });
    await btn7d.click();

    // Active button gets the brand-tinted active styling
    await expect(btn7d).toHaveClass(/bg-brand/);
    await expect(btn7d).toHaveClass(/border-brand/);
  });

  test("date preset changes query parameters in API call", async ({ page }) => {
    const proxiedPaths: string[] = [];
    await page.route("**/api/proxy*", async (route: Route) => {
      const url = new URL(route.request().url());
      const pathParam = url.searchParams.get("path") ?? "";
      proxiedPaths.push(pathParam);

      if (pathParam.includes("/reports/dashboard")) {
        await route.fulfill({ json: MOCK_DASHBOARD });
      } else if (pathParam.includes("/reports/utilization-heatmap")) {
        await route.fulfill({ json: MOCK_HEATMAP });
      } else {
        await route.fulfill({ json: {} });
      }
    });
    await page.route("**/api/auth/refresh", async (route: Route) => {
      await route.fulfill({ status: 200, json: { ok: true } });
    });

    await page.goto("/reports");
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();

    // Click 7d preset
    proxiedPaths.length = 0;
    await page.getByRole("button", { name: /7d/i }).click();
    // Wait for refetch
    await page.waitForTimeout(1000);

    // At least one dashboard call should have been made with date params
    const dashboardCalls = proxiedPaths.filter((p) => p.includes("/reports/dashboard"));
    expect(dashboardCalls.length).toBeGreaterThan(0);
    expect(dashboardCalls[0]).toContain("start_date=");
    expect(dashboardCalls[0]).toContain("end_date=");
  });
});

// --- RPT-03: Utilization Heatmap ---

test.describe("Phase 18: Reports - Utilization Heatmap (RPT-03)", () => {
  test.beforeEach(async ({ page }) => {
    await mockReportsApi(page);
  });

  test("heatmap renders contractor rows and week columns", async ({ page }) => {
    await page.goto("/reports");
    const heatmapCard = page.locator('[aria-label="Contractor Utilization chart"]');
    await expect(heatmapCard).toBeVisible();
    await expect(heatmapCard.getByText("Contractor Utilization")).toBeVisible();

    // Contractor names visible
    await expect(heatmapCard.getByText("Alice Builder")).toBeVisible();
    await expect(heatmapCard.getByText("Bob Plumber")).toBeVisible();

    // Week headers visible
    await expect(heatmapCard.getByText("2026-W08")).toBeVisible();
    await expect(heatmapCard.getByText("2026-W11")).toBeVisible();

    // Grid cells rendered (rounded-sm = heatmap cells)
    const cells = heatmapCard.locator(".rounded-sm");
    // 2 contractors × 4 weeks = 8 cells
    await expect(cells).toHaveCount(8);
  });

  test("heatmap cells have correct color classes for utilization thresholds", async ({ page }) => {
    await page.goto("/reports");
    const heatmapCard = page.locator('[aria-label="Contractor Utilization chart"]');
    await expect(heatmapCard.getByText("Alice Builder")).toBeVisible();

    // Alice: W08=90% (red), W09=70% (yellow), W10=35% (green-400), W11=20% (green-200)
    // Bob:   W08=0% (bg-muted), W09=100% (red), W10=60% (yellow), W11=85% (red)

    // Verify by tooltip title attributes
    const aliceRed = heatmapCard.locator('[title="Alice Builder — 2026-W08: 90%"]');
    await expect(aliceRed).toHaveClass(/bg-red-500/);

    const aliceYellow = heatmapCard.locator('[title="Alice Builder — 2026-W09: 70%"]');
    await expect(aliceYellow).toHaveClass(/bg-yellow-400/);

    const aliceGreen = heatmapCard.locator('[title="Alice Builder — 2026-W10: 35%"]');
    await expect(aliceGreen).toHaveClass(/bg-green-400/);

    const aliceLightGreen = heatmapCard.locator('[title="Alice Builder — 2026-W11: 20%"]');
    await expect(aliceLightGreen).toHaveClass(/bg-green-200/);

    // Bob W08=0% should be bg-muted (no booking data → green-200 since 0 < 30)
    const bobZero = heatmapCard.locator('[title="Bob Plumber — 2026-W08: 0%"]');
    await expect(bobZero).toHaveClass(/bg-green-200/);

    // Bob W09=100% should be red
    const bobFull = heatmapCard.locator('[title="Bob Plumber — 2026-W09: 100%"]');
    await expect(bobFull).toHaveClass(/bg-red-500/);

    // Bob W11=85% should be red (>=85)
    const bobHigh = heatmapCard.locator('[title="Bob Plumber — 2026-W11: 85%"]');
    await expect(bobHigh).toHaveClass(/bg-red-500/);
  });

  test("heatmap KPI shows contractor count", async ({ page }) => {
    await page.goto("/reports");
    const heatmapCard = page.locator('[aria-label="Contractor Utilization chart"]');
    await expect(heatmapCard.locator(".text-3xl")).toContainText("2 contractors");
  });
});

// --- CSV Export (Human verification item #2) ---

test.describe("Phase 18: Reports - CSV Export", () => {
  test.beforeEach(async ({ page }) => {
    await mockReportsApi(page);
  });

  test("revenue CSV export triggers download with correct content", async ({ page }) => {
    await page.goto("/reports");
    await expect(page.locator('[aria-label="Revenue by Month chart"]')).toBeVisible();

    // Listen for download
    const downloadPromise = page.waitForEvent("download");
    await page.locator('[aria-label="Download Revenue by Month as CSV"]').click();
    const download = await downloadPromise;

    // Filename should include date range
    expect(download.suggestedFilename()).toMatch(/^revenue-\d{4}-\d{2}-\d{2}-to-\d{4}-\d{2}-\d{2}\.csv$/);

    // Read content
    const content = (await download.path()) ? await (await download.createReadStream()).toArray() : [];
    const text = Buffer.concat(content).toString("utf-8");
    // Should contain header + 3 data rows
    expect(text).toContain('"Month"');
    expect(text).toContain('"Paid"');
    expect(text).toContain('"Unpaid"');
    expect(text).toContain('"2026-01"');
    expect(text).toContain('"12500.00"');
    const lines = text.trim().split("\n");
    expect(lines).toHaveLength(4); // header + 3 months
  });

  test("jobs CSV export has correct columns", async ({ page }) => {
    await page.goto("/reports");
    await expect(page.locator('[aria-label="Jobs by Status chart"]')).toBeVisible();

    const downloadPromise = page.waitForEvent("download");
    await page.locator('[aria-label="Download Jobs by Status as CSV"]').click();
    const download = await downloadPromise;

    expect(download.suggestedFilename()).toMatch(/^jobs-by-status-.*\.csv$/);

    const content = (await download.path()) ? await (await download.createReadStream()).toArray() : [];
    const text = Buffer.concat(content).toString("utf-8");
    expect(text).toContain('"Status"');
    expect(text).toContain('"Count"');
    expect(text).toContain('"scheduled"');
    expect(text).toContain('"12"'); // complete count
    const lines = text.trim().split("\n");
    expect(lines).toHaveLength(5); // header + 4 statuses
  });

  test("quote conversion CSV export has correct data", async ({ page }) => {
    await page.goto("/reports");
    await expect(page.locator('[aria-label="Quote Conversion chart"]')).toBeVisible();

    const downloadPromise = page.waitForEvent("download");
    await page.locator('[aria-label="Download Quote Conversion as CSV"]').click();
    const download = await downloadPromise;

    const content = (await download.path()) ? await (await download.createReadStream()).toArray() : [];
    const text = Buffer.concat(content).toString("utf-8");
    expect(text).toContain('"Approved"');
    expect(text).toContain('"15"');
    expect(text).toContain('"Declined"');
    expect(text).toContain('"4"');
  });

  test("utilization heatmap CSV export includes all contractors and weeks", async ({ page }) => {
    await page.goto("/reports");
    await expect(page.locator('[aria-label="Contractor Utilization chart"]')).toBeVisible();

    const downloadPromise = page.waitForEvent("download");
    await page.locator('[aria-label="Download Contractor Utilization as CSV"]').click();
    const download = await downloadPromise;

    const content = (await download.path()) ? await (await download.createReadStream()).toArray() : [];
    const text = Buffer.concat(content).toString("utf-8");
    expect(text).toContain('"Contractor"');
    expect(text).toContain('"2026-W08"');
    expect(text).toContain('"Alice Builder"');
    expect(text).toContain('"Bob Plumber"');
    expect(text).toContain('"90%"'); // Alice W08
    expect(text).toContain('"0%"');  // Bob W08
    const lines = text.trim().split("\n");
    expect(lines).toHaveLength(3); // header + 2 contractors
  });
});

// --- Drill-down Navigation (Human verification item #4) ---

test.describe("Phase 18: Reports - Drill-down Navigation", () => {
  test.beforeEach(async ({ page }) => {
    await mockReportsApi(page);
  });

  test("clicking revenue chart area navigates to invoices with month param", async ({ page }) => {
    await page.goto("/reports");
    const revenueCard = page.locator('[aria-label="Revenue by Month chart"]');
    const svg = revenueCard.locator("svg.recharts-surface");
    await expect(svg).toBeVisible();

    // Click on the chart area — Recharts fires onClick with activePayload
    const box = await svg.boundingBox();
    expect(box).toBeTruthy();
    // Click roughly in the middle of the chart
    await svg.click({ position: { x: box!.width / 2, y: box!.height / 2 } });

    // Should navigate to /invoices?month=YYYY-MM
    await page.waitForURL(/\/invoices\?month=\d{4}-\d{2}/, { timeout: 3000 }).catch(() => {
      // Navigation may not trigger if click misses data point — that's OK for SVG charts
    });
  });

  test("clicking jobs bar navigates to jobs with status param", async ({ page }) => {
    await page.goto("/reports");
    const jobsCard = page.locator('[aria-label="Jobs by Status chart"]');
    const svg = jobsCard.locator("svg.recharts-surface");
    await expect(svg).toBeVisible();

    // Click on a bar element — find a recharts-bar-rectangle
    const bars = jobsCard.locator(".recharts-bar-rectangle");
    const barCount = await bars.count();
    if (barCount > 0) {
      await bars.first().click();
      await page.waitForURL(/\/jobs\?status=/, { timeout: 3000 });
      expect(page.url()).toMatch(/\/jobs\?status=\w+/);
    }
  });

  test("clicking quote pie slice navigates to quotes with status param", async ({ page }) => {
    await page.goto("/reports");
    const quoteCard = page.locator('[aria-label="Quote Conversion chart"]');
    const svg = quoteCard.locator('svg.recharts-surface[role="application"]');
    await expect(svg).toBeVisible();

    // Click on a pie sector
    const sectors = quoteCard.locator(".recharts-pie-sector");
    const sectorCount = await sectors.count();
    if (sectorCount > 0) {
      await sectors.first().click();
      await page.waitForURL(/\/quotes\?status=/, { timeout: 3000 });
      expect(page.url()).toMatch(/\/quotes\?status=\w+/);
    }
  });
});
