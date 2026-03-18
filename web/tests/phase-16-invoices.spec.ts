import { test, expect } from "@playwright/test";

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const MOCK_JOB = {
  id: "job-1",
  description: "Kitchen Renovation",
  client_name: "John Smith",
  client_id: "client-1",
  status: "complete",
  company_id: "co-1",
};

const MOCK_INVOICE_UNPAID = {
  id: "inv-1",
  company_id: "co-1",
  job_id: "job-1",
  quote_id: "quote-1",
  invoice_number: "INV-0001",
  status: "unpaid",
  tax_rate: "10",
  discount_type: null,
  discount_value: "0",
  due_date: "2026-04-15T00:00:00Z",
  issued_at: "2026-03-15T10:00:00Z",
  finalized_at: "2026-03-15T10:00:00Z",
  amount_paid: "0",
  line_items: [
    {
      id: "ili-1",
      invoice_id: "inv-1",
      item_type: "labor",
      description: "Demolition work",
      quantity: "8",
      unit: "hr",
      unit_price: "75",
      sort_order: 0,
    },
    {
      id: "ili-2",
      invoice_id: "inv-1",
      item_type: "material",
      description: "Tiles",
      quantity: "20",
      unit: "sqm",
      unit_price: "45",
      sort_order: 1,
    },
  ],
  subtotal: "1500.00",
  discount_amount: "0.00",
  tax_amount: "150.00",
  total: "1650.00",
  version: 1,
  created_at: "2026-03-15T10:00:00Z",
  updated_at: "2026-03-15T10:00:00Z",
};

const MOCK_INVOICE_OVERDUE = {
  ...MOCK_INVOICE_UNPAID,
  id: "inv-overdue",
  invoice_number: "INV-0004",
  due_date: "2026-01-01T00:00:00Z",
};

const MOCK_INVOICE_PARTIAL = {
  ...MOCK_INVOICE_UNPAID,
  id: "inv-2",
  invoice_number: "INV-0002",
  status: "partially_paid",
  amount_paid: "500.00",
};

const MOCK_INVOICE_PAID = {
  ...MOCK_INVOICE_UNPAID,
  id: "inv-3",
  invoice_number: "INV-0003",
  status: "paid",
  amount_paid: "1650.00",
};

const ALL_INVOICES = [
  MOCK_INVOICE_UNPAID,
  MOCK_INVOICE_PARTIAL,
  MOCK_INVOICE_PAID,
  MOCK_INVOICE_OVERDUE,
];

const MOCK_AUTH_USER = {
  id: "user-1",
  email: "admin@test.com",
  role: "admin",
  company_id: "co-1",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Set up API route interception for the invoices list page.
 * Intercepts auth, invoices, and jobs endpoints via the proxy pattern.
 */
async function setupListRoutes(
  page: import("@playwright/test").Page,
  invoices = ALL_INVOICES,
  jobs = [MOCK_JOB]
) {
  // Auth endpoint
  await page.route("**/api/auth/me", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(MOCK_AUTH_USER) })
  );

  // Proxy API calls
  await page.route("**/api/proxy**", async (route) => {
    const url = new URL(route.request().url());
    const path = url.searchParams.get("path") || "";

    if (path.includes("/api/v1/invoices")) {
      return route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(invoices),
      });
    }
    if (path.includes("/api/v1/jobs")) {
      return route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(jobs),
      });
    }

    return route.continue();
  });
}

/**
 * Set up API route interception for the invoice detail page.
 */
async function setupDetailRoutes(
  page: import("@playwright/test").Page,
  invoice: typeof MOCK_INVOICE_UNPAID,
  job = MOCK_JOB,
  patchHandler?: (body: unknown) => typeof MOCK_INVOICE_UNPAID
) {
  await page.route("**/api/auth/me", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(MOCK_AUTH_USER) })
  );

  await page.route("**/api/proxy**", async (route) => {
    const url = new URL(route.request().url());
    const path = url.searchParams.get("path") || "";
    const method = route.request().method();

    // PATCH payment
    if (method === "PATCH" && path.includes("/payment")) {
      const body = route.request().postDataJSON();
      const updated = patchHandler ? patchHandler(body) : invoice;
      return route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(updated),
      });
    }

    // GET single invoice
    if (path.includes("/api/v1/invoices/") && !path.includes("/pdf")) {
      return route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(invoice),
      });
    }

    // PDF endpoint
    if (path.includes("/pdf")) {
      return route.fulfill({
        status: 200,
        contentType: "application/pdf",
        body: Buffer.from([0x25, 0x50, 0x44, 0x46]),
      });
    }

    // Jobs
    if (path.includes("/api/v1/jobs")) {
      return route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(job),
      });
    }

    return route.continue();
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe("Phase 16 -- Invoices", () => {
  // =========================================================================
  // LIST TESTS
  // =========================================================================

  test("invoices list: renders payment status tabs with counts", async ({ page }) => {
    await setupListRoutes(page);
    await page.goto("/invoices");

    // Wait for data to load
    await expect(page.getByText("INV-0001")).toBeVisible({ timeout: 10000 });

    // Verify all 6 tab buttons are visible
    for (const label of ["All", "Unpaid", "Partially Paid", "Paid", "Overdue", "Draft"]) {
      await expect(page.getByRole("button", { name: new RegExp(`^${label}`) })).toBeVisible();
    }

    // Verify "All" tab shows count "(4)"
    const allTab = page.getByRole("button", { name: /^All/ });
    await expect(allTab).toContainText("(4)");

    // "Unpaid" count: 2 (INV-0001 future due + INV-0004 overdue, both status=unpaid)
    const unpaidTab = page.getByRole("button", { name: /^Unpaid/ });
    await expect(unpaidTab).toContainText("(2)");
  });

  test("invoices list: overdue rows have red left border", async ({ page }) => {
    await setupListRoutes(page);
    await page.goto("/invoices");

    // Wait for data
    await expect(page.getByText("INV-0004")).toBeVisible({ timeout: 10000 });

    // Find the row containing the overdue invoice INV-0004
    const overdueRow = page.locator("tr").filter({ hasText: "INV-0004" });
    await expect(overdueRow).toBeVisible();

    // Check the overdue row has the red left border classes
    await expect(overdueRow).toHaveClass(/border-l-2/);
    await expect(overdueRow).toHaveClass(/border-red-400/);

    // The StatusBadge for overdue should render "overdue" (or "Overdue")
    const statusCell = overdueRow.locator("td").nth(6); // 7th column = Status
    await expect(statusCell).toContainText(/overdue/i);
  });

  test("invoices list: filters by status tab", async ({ page }) => {
    await setupListRoutes(page);
    await page.goto("/invoices");

    // Wait for data
    await expect(page.getByText("INV-0001")).toBeVisible({ timeout: 10000 });

    // Click "Paid" tab (use exact to avoid matching "Partially Paid")
    await page.getByRole("button", { name: /^Paid\(/ }).click();

    // URL should contain tab=paid
    await expect(page).toHaveURL(/tab=paid/);

    // Only the paid invoice row should be visible in the table body
    const tableBody = page.locator("tbody");
    await expect(tableBody.locator("tr")).toHaveCount(1);
    await expect(tableBody).toContainText("INV-0003");
  });

  test("invoices list: click row navigates to detail", async ({ page }) => {
    await setupListRoutes(page);
    await page.goto("/invoices");

    // Wait for data
    await expect(page.getByText("INV-0001")).toBeVisible({ timeout: 10000 });

    // Click the first table row in tbody
    await page.locator("tbody tr").first().click();

    // Should navigate to an invoice detail page
    await expect(page).toHaveURL(/\/invoices\/inv-/);
  });

  // =========================================================================
  // DETAIL TESTS
  // =========================================================================

  test("invoice detail: shows payment summary (Total/Paid/Balance)", async ({ page }) => {
    await setupDetailRoutes(page, MOCK_INVOICE_PARTIAL);
    await page.goto("/invoices/inv-2");

    // Wait for content to load
    await expect(page.getByRole("heading", { name: /INV-0002/ })).toBeVisible({ timeout: 10000 });

    // Payment Summary card shows Total, Paid, Balance
    // The detail page renders: ${Number(val).toFixed(2)} — no comma formatting
    // Total: $1650.00
    await expect(page.getByText("$1650.00").first()).toBeVisible();

    // Paid: $500.00
    await expect(page.getByText("$500.00").first()).toBeVisible();

    // Balance: $1150.00
    await expect(page.getByText("$1150.00").first()).toBeVisible();
  });

  test("invoice detail: record partial payment updates balance", async ({ page }) => {
    let capturedBody: unknown = null;

    await setupDetailRoutes(
      page,
      MOCK_INVOICE_UNPAID,
      MOCK_JOB,
      (body) => {
        capturedBody = body;
        return {
          ...MOCK_INVOICE_UNPAID,
          status: "partially_paid",
          amount_paid: "200.00",
        };
      }
    );

    await page.goto("/invoices/inv-1");
    await expect(page.getByRole("heading", { name: /INV-0001/ })).toBeVisible({ timeout: 10000 });

    // Click "Record Payment" button (in the Payment section card, not sidebar)
    // There are two "Record Payment" buttons (main + sidebar). Click the first visible one.
    const recordBtn = page.getByRole("button", { name: "Record Payment" }).first();
    await recordBtn.click();

    // Fill the payment amount input
    const amountInput = page.locator('input[type="number"]').first();
    await amountInput.fill("200");

    // Click "Save Payment" button
    await page.getByRole("button", { name: "Save Payment" }).click();

    // Verify the PATCH was called with the correct body
    // The handler accumulates: newAmountPaid = 0 + 200 = 200, status = "partially_paid"
    await expect.poll(() => capturedBody).toBeTruthy();
    const body = capturedBody as { status: string; amount_paid: number };
    expect(body.status).toBe("partially_paid");
    expect(body.amount_paid).toBe(200);
  });

  test("invoice detail: mark fully paid updates status", async ({ page }) => {
    let capturedBody: unknown = null;

    await setupDetailRoutes(
      page,
      MOCK_INVOICE_PARTIAL,
      MOCK_JOB,
      (body) => {
        capturedBody = body;
        return {
          ...MOCK_INVOICE_PARTIAL,
          status: "paid",
          amount_paid: "1650.00",
        };
      }
    );

    await page.goto("/invoices/inv-2");
    await expect(page.getByRole("heading", { name: /INV-0002/ })).toBeVisible({ timeout: 10000 });

    // Click "Mark Fully Paid" button
    await page.getByRole("button", { name: "Mark Fully Paid" }).click();

    // Verify the PATCH was called with status: "paid" and amount_paid matching total
    await expect.poll(() => capturedBody).toBeTruthy();
    const body = capturedBody as { status: string; amount_paid: number };
    expect(body.status).toBe("paid");
    expect(body.amount_paid).toBe(1650);
  });

  test("invoice pdf: download triggers file save", async ({ page }) => {
    let pdfEndpointCalled = false;

    await setupDetailRoutes(page, MOCK_INVOICE_UNPAID);

    // Add a secondary route to track the PDF fetch specifically
    await page.route("**/api/proxy**", async (route) => {
      const url = new URL(route.request().url());
      const path = url.searchParams.get("path") || "";
      if (path.includes("/pdf")) {
        pdfEndpointCalled = true;
      }
      await route.fallback();
    });

    await page.goto("/invoices/inv-1");
    await expect(page.getByRole("heading", { name: /INV-0001/ })).toBeVisible({ timeout: 10000 });

    // Inject spy to capture the anchor element download attribute.
    // The implementation does: a = document.createElement("a"); a.download = "invoice-{number}.pdf"; a.click()
    await page.evaluate(() => {
      const origCreate = document.createElement.bind(document);
      (window as unknown as Record<string, unknown>).__pdfDownloadFilename = null;
      document.createElement = function (tag: string, options?: ElementCreationOptions) {
        const el = origCreate(tag, options);
        if (tag === "a") {
          const origClick = el.click.bind(el);
          el.click = function () {
            (window as unknown as Record<string, unknown>).__pdfDownloadFilename =
              (el as HTMLAnchorElement).download;
            origClick();
          };
        }
        return el;
      } as typeof document.createElement;
    });

    // Click "Download PDF" button
    await page.getByRole("button", { name: "Download PDF" }).click();

    // Wait for the fetch + blob + anchor click sequence to complete
    await page.waitForTimeout(1500);

    // 1. Verify the PDF API endpoint was called
    expect(pdfEndpointCalled).toBe(true);

    // 2. Verify the download filename was set correctly
    const downloadFilename = await page.evaluate(
      () => (window as unknown as Record<string, unknown>).__pdfDownloadFilename
    );
    expect(downloadFilename).toBe("invoice-INV-0001.pdf");

    // 3. Verify page did not navigate away
    await expect(page).toHaveURL(/\/invoices\/inv-1/);

    // 4. Button still enabled after download
    await expect(
      page.getByRole("button", { name: "Download PDF" })
    ).toBeEnabled();
  });
});
