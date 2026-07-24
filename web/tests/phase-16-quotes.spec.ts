import { test, expect } from "@playwright/test";

// ---------------------------------------------------------------------------
// Mock data factories
// ---------------------------------------------------------------------------

const MOCK_JOB = {
  id: "job-1",
  description: "Kitchen Renovation",
  client_name: "John Smith",
  client_id: "client-1",
  status: "quote",
  company_id: "co-1",
};

const MOCK_QUOTE_DRAFT = {
  id: "aabbcc-1111-2222-3333-444455556666",
  company_id: "co-1",
  job_id: "job-1",
  status: "draft",
  revision_number: 1,
  tax_rate: "10",
  discount_type: null,
  discount_value: "0",
  expiry_date: "2026-04-15",
  sent_at: null,
  viewed_at: null,
  approved_at: null,
  declined_at: null,
  decline_reason: null,
  decline_detail: null,
  admin_notes: "Internal note",
  line_items: [
    {
      id: "li-1",
      quote_id: "aabbcc-1111-2222-3333-444455556666",
      item_type: "labor",
      description: "Demolition work",
      quantity: "8",
      unit: "hr",
      unit_price: "75",
      sort_order: 0,
    },
    {
      id: "li-2",
      quote_id: "aabbcc-1111-2222-3333-444455556666",
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

const MOCK_QUOTE_SENT = {
  ...MOCK_QUOTE_DRAFT,
  id: "bbccdd-2222-3333-4444-555566667777",
  status: "sent",
  sent_at: "2026-03-16T09:00:00Z",
};

const MOCK_QUOTE_APPROVED = {
  ...MOCK_QUOTE_DRAFT,
  id: "ccddee-3333-4444-5555-666677778888",
  status: "approved",
  sent_at: "2026-03-16T09:00:00Z",
  viewed_at: "2026-03-16T12:00:00Z",
  approved_at: "2026-03-17T08:00:00Z",
};

const MOCK_QUOTE_DECLINED = {
  ...MOCK_QUOTE_DRAFT,
  id: "ddeeff-4444-5555-6666-777788889999",
  status: "declined",
  sent_at: "2026-03-16T09:00:00Z",
  viewed_at: "2026-03-16T12:00:00Z",
  declined_at: "2026-03-17T14:00:00Z",
  decline_reason: "Too expensive",
  decline_detail: "Budget constraints prevent approval at this price.",
};

const MOCK_TEMPLATE = {
  id: "tmpl-1",
  company_id: "co-1",
  name: "Standard Renovation",
  description: "Basic renovation template",
  line_items_json: JSON.stringify([
    {
      item_type: "labor",
      description: "Site prep",
      quantity: "4",
      unit: "hr",
      unit_price: "60",
      sort_order: 0,
    },
  ]),
  tax_rate: "8",
};

const ALL_QUOTES = [MOCK_QUOTE_DRAFT, MOCK_QUOTE_SENT, MOCK_QUOTE_APPROVED];

// ---------------------------------------------------------------------------
// Helper: set up API route interception for proxy calls
// ---------------------------------------------------------------------------

/**
 * Intercepts /api/proxy requests and responds with mock data based on path.
 * Also intercepts /api/auth/* to prevent auth redirects.
 */
function setupProxyRoutes(
  page: import("@playwright/test").Page,
  overrides?: {
    quotes?: unknown[];
    singleQuote?: unknown;
    jobs?: unknown[];
    singleJob?: unknown;
    templates?: unknown[];
    sendResponse?: unknown;
    pdfResponse?: boolean;
  }
) {
  const quotes = overrides?.quotes ?? ALL_QUOTES;
  const jobs = overrides?.jobs ?? [MOCK_JOB];
  const singleQuote = overrides?.singleQuote ?? MOCK_QUOTE_DRAFT;
  const singleJob = overrides?.singleJob ?? MOCK_JOB;
  const templates = overrides?.templates ?? [];

  // Track send calls for assertion
  let sendCalled = false;
  const sendPromise = new Promise<void>((resolve) => {
    // We'll resolve this when send is intercepted
    page.on("request", (req) => {
      if (req.url().includes("/api/proxy") && req.method() === "POST") {
        const url = new URL(req.url());
        const path = url.searchParams.get("path") || "";
        if (path.includes("/send")) {
          sendCalled = true;
          resolve();
        }
      }
    });
  });

  return {
    sendPromise,
    isSendCalled: () => sendCalled,
    setup: async () => {
      // Intercept auth routes to prevent login redirects
      await page.route("**/api/auth/**", async (route) => {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ access_token: "mock-token" }),
        });
      });

      // Intercept proxy routes
      await page.route("**/api/proxy**", async (route) => {
        const url = new URL(route.request().url());
        const path = url.searchParams.get("path") || "";
        const method = route.request().method();

        // POST /api/v1/quotes/{id}/send
        if (method === "POST" && path.includes("/send")) {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify({
              ...singleQuote,
              status: "sent",
              sent_at: "2026-03-18T10:00:00Z",
            }),
          });
          return;
        }

        // GET /api/v1/quotes/templates
        if (path.includes("/quotes/templates")) {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify(templates),
          });
          return;
        }

        // GET /api/v1/quotes/{id}/pdf
        if (path.includes("/pdf")) {
          if (overrides?.pdfResponse) {
            await route.fulfill({
              status: 200,
              contentType: "application/pdf",
              body: Buffer.from([0x25, 0x50, 0x44, 0x46]),
            });
          } else {
            await route.fulfill({
              status: 200,
              contentType: "application/pdf",
              body: Buffer.from([0x25, 0x50, 0x44, 0x46]),
            });
          }
          return;
        }

        // GET /api/v1/quotes/{id} (single quote - must check before list)
        if (
          path.match(/\/api\/v1\/quotes\/[a-zA-Z0-9-]+$/) &&
          !path.endsWith("/quotes/")
        ) {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify(singleQuote),
          });
          return;
        }

        // GET /api/v1/quotes/ (list)
        if (path.includes("/quotes")) {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify(quotes),
          });
          return;
        }

        // GET /api/v1/invoices/for-job/{id}
        if (path.includes("/invoices/for-job/")) {
          await route.fulfill({
            status: 404,
            contentType: "application/json",
            body: JSON.stringify({ detail: "Not found" }),
          });
          return;
        }

        // GET /api/v1/jobs/{id} (single job)
        if (
          path.match(/\/api\/v1\/jobs\/[a-zA-Z0-9-]+$/) &&
          !path.endsWith("/jobs/")
        ) {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify(singleJob),
          });
          return;
        }

        // GET /api/v1/jobs/ (list)
        if (path.includes("/jobs")) {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify(jobs),
          });
          return;
        }

        // Default fallback
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify([]),
        });
      });
    },
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe("Phase 16 -- Quotes", () => {
  // =========================================================================
  // Quotes List Tests
  // =========================================================================

  test("quotes list: renders status tabs with count badges", async ({
    page,
  }) => {
    const routes = setupProxyRoutes(page);
    await routes.setup();

    await page.goto("/quotes");
    await page.waitForLoadState("networkidle");

    // All 7 tab buttons should be visible
    const tabLabels = [
      "All",
      "Draft",
      "Sent",
      "Viewed",
      "Approved",
      "Declined",
      "Expired",
    ];
    for (const label of tabLabels) {
      await expect(
        page.locator("button", { hasText: new RegExp(`^${label}`) })
      ).toBeVisible();
    }

    // "All" tab should show count (3) — 3 quotes (draft, sent, approved)
    await expect(
      page.locator("button", { hasText: /All/ }).locator("span", { hasText: "(3)" })
    ).toBeVisible();

    // "Draft" tab should show count (1)
    await expect(
      page
        .locator("button", { hasText: /Draft/ })
        .locator("span", { hasText: "(1)" })
    ).toBeVisible();
  });

  test("quotes list: filters by status tab", async ({ page }) => {
    const routes = setupProxyRoutes(page);
    await routes.setup();

    await page.goto("/quotes");
    await page.waitForLoadState("networkidle");

    // Verify all 3 rows visible initially (All tab)
    await expect(page.locator("tbody tr")).toHaveCount(3);

    // Click "Sent" tab
    await page.locator("button", { hasText: /^Sent/ }).click();

    // URL should contain tab=sent
    await expect(page).toHaveURL(/tab=sent/);

    // Only 1 row visible (the sent quote)
    await expect(page.locator("tbody tr")).toHaveCount(1);
  });

  test("quotes list: search filters quotes", async ({ page }) => {
    const routes = setupProxyRoutes(page);
    await routes.setup();

    await page.goto("/quotes");
    await page.waitForLoadState("networkidle");

    // Initially 3 rows
    await expect(page.locator("tbody tr")).toHaveCount(3);

    // Type in search input
    await page.getByPlaceholder("Search quotes...").fill("Kitchen");

    // Wait for debounce (300ms in the component)
    await page.waitForTimeout(400);

    // All 3 quotes share job "Kitchen Renovation" so all should still match
    await expect(page.locator("tbody tr")).toHaveCount(3);

    // Search for something that won't match
    await page.getByPlaceholder("Search quotes...").fill("Nonexistent");
    await page.waitForTimeout(400);

    // No matching rows -- empty state should appear
    await expect(page.locator("tbody tr")).toHaveCount(0);
  });

  test("quotes list: click row navigates to detail", async ({ page }) => {
    const routes = setupProxyRoutes(page);
    await routes.setup();

    await page.goto("/quotes");
    await page.waitForLoadState("networkidle");

    // Click first table row
    await page.locator("tbody tr").first().click();

    // Should navigate to quote detail
    await expect(page).toHaveURL(/\/quotes\//);
  });

  // =========================================================================
  // Quote Detail Tests
  // =========================================================================

  test("quote detail: shows two-column layout with line items", async ({
    page,
  }) => {
    const routes = setupProxyRoutes(page);
    await routes.setup();

    await page.goto("/quotes/aabbcc-1111-2222-3333-444455556666");
    await page.waitForLoadState("networkidle");

    // Two-column grid exists
    await expect(
      page.locator(".grid.grid-cols-1.lg\\:grid-cols-\\[1fr_360px\\]")
    ).toBeVisible();

    // "Line Items" card heading visible
    await expect(page.getByText("Line Items", { exact: true })).toBeVisible();

    // Line item description visible
    await expect(page.getByText("Demolition work")).toBeVisible();

    // Financial summary values
    await expect(page.getByText("Subtotal").first()).toBeVisible();
    await expect(page.getByText("$1500.00").first()).toBeVisible();
    await expect(page.getByText("$1650.00").first()).toBeVisible();
  });

  test("quote detail: shows context-sensitive action buttons", async ({
    page,
  }) => {
    // Test 1: Draft quote shows Send, Edit, Download PDF
    const draftRoutes = setupProxyRoutes(page, {
      singleQuote: MOCK_QUOTE_DRAFT,
    });
    await draftRoutes.setup();

    await page.goto("/quotes/aabbcc-1111-2222-3333-444455556666");
    await page.waitForLoadState("networkidle");

    await expect(
      page.getByRole("button", { name: "Send Quote" })
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Edit" })).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Download PDF" })
    ).toBeVisible();

    // Test 2: Navigate to declined quote
    // Clear routes and set up new ones
    await page.unrouteAll();

    const declinedRoutes = setupProxyRoutes(page, {
      singleQuote: MOCK_QUOTE_DECLINED,
    });
    await declinedRoutes.setup();

    await page.goto("/quotes/ddeeff-4444-5555-6666-777788889999");
    await page.waitForLoadState("networkidle");

    // Declined banner visible (inside the alert, not the activity log)
    await expect(page.locator(".bg-red-50").getByText("Declined by client")).toBeVisible();

    // bg-red-50 alert
    await expect(page.locator(".bg-red-50")).toBeVisible();

    // Revise & Resend button visible (appears in both alert and sidebar -- use first)
    await expect(
      page.getByRole("button", { name: /Revise.*Resend/ }).first()
    ).toBeVisible();
  });

  // =========================================================================
  // Quote Builder Tests
  // =========================================================================

  test("quote builder: add and remove line items", async ({ page }) => {
    const routes = setupProxyRoutes(page, { templates: [] });
    await routes.setup();

    await page.goto("/quotes/new/edit?job_id=job-1");
    await page.waitForLoadState("networkidle");

    // Should have 1 default row
    const rows = page.locator("tbody tr");
    await expect(rows).toHaveCount(1);

    // Click "Add Row"
    await page.getByRole("button", { name: "Add Row" }).click();
    await expect(rows).toHaveCount(2);

    // Remove the second row (click the X / delete button)
    await page
      .getByRole("button", { name: "Delete row" })
      .nth(1)
      .click();
    await expect(rows).toHaveCount(1);
  });

  test("quote builder: inline editing updates financial summary", async ({
    page,
  }) => {
    const routes = setupProxyRoutes(page, { templates: [] });
    await routes.setup();

    await page.goto("/quotes/new/edit?job_id=job-1");
    await page.waitForLoadState("networkidle");

    // Fill quantity and unit price in first row
    // The form default has quantity "1" and unit_price "0"
    const qtyInput = page.locator('input[name="line_items.0.quantity"]');
    const priceInput = page.locator('input[name="line_items.0.unit_price"]');

    // Clear and type values to ensure React onChange fires properly
    await qtyInput.click();
    await qtyInput.fill("");
    await qtyInput.type("10");

    await priceInput.click();
    await priceInput.fill("");
    await priceInput.type("100");

    // Click outside the input to trigger any blur-based updates
    await page.locator("h1").click();

    // Wait for React to re-render with updated computed values
    // The sticky financial summary footer shows subtotal as $1000.00
    await expect(page.getByText("$1000.00").first()).toBeVisible({ timeout: 10000 });
  });

  test("quote builder: drag reorder line items", async ({ page }) => {
    const routes = setupProxyRoutes(page, { templates: [] });
    await routes.setup();

    await page.goto("/quotes/new/edit?job_id=job-1");
    await page.waitForLoadState("networkidle");

    // Add a second row so we have 2 rows to reorder
    await page.getByRole("button", { name: "Add Row" }).click();
    await expect(page.locator("tbody tr")).toHaveCount(2);

    // Fill first row description so we can track reorder
    const firstDesc = page.locator('input[name="line_items.0.description"]');
    await firstDesc.fill("First Item");

    // Fill second row description
    const secondDesc = page.locator('input[name="line_items.1.description"]');
    await secondDesc.fill("Second Item");

    // Verify drag handles exist with proper aria-label
    const dragHandles = page.getByRole("button", {
      name: "Drag to reorder",
    });
    await expect(dragHandles).toHaveCount(2);

    // Perform the drag: move second row's handle onto the first row's handle.
    // dnd-kit's PointerSensor needs a real pointer gesture — a single dragTo()
    // doesn't cross the 5px activation threshold or feed incremental moves to
    // collision detection, so we drive the mouse manually in steps instead.
    const sourceHandle = dragHandles.nth(1);
    const targetHandle = dragHandles.first();

    const sourceBox = await sourceHandle.boundingBox();
    const targetBox = await targetHandle.boundingBox();
    if (!sourceBox || !targetBox) {
      throw new Error("Drag handles are not visible");
    }
    const startX = sourceBox.x + sourceBox.width / 2;
    const startY = sourceBox.y + sourceBox.height / 2;
    const endX = targetBox.x + targetBox.width / 2;
    const endY = targetBox.y + targetBox.height / 2;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    // Cross the activation distance (>5px) toward the target.
    await page.mouse.move(startX, startY - 8, { steps: 3 });
    // Move over the target row in increments so collision detection fires.
    await page.mouse.move(endX, endY, { steps: 12 });
    // Settle slightly above the target center, then drop.
    await page.mouse.move(endX, endY - 4, { steps: 3 });
    await page.mouse.up();

    // After drag, the descriptions should be swapped:
    // line_items.0 should now be "Second Item", line_items.1 should be "First Item"
    await expect(
      page.locator('input[name="line_items.0.description"]')
    ).toHaveValue("Second Item");
    await expect(
      page.locator('input[name="line_items.1.description"]')
    ).toHaveValue("First Item");
  });

  test("quote builder: load from template populates fields", async ({
    page,
  }) => {
    const routes = setupProxyRoutes(page, { templates: [MOCK_TEMPLATE] });
    await routes.setup();

    await page.goto("/quotes/new/edit?job_id=job-1");
    await page.waitForLoadState("networkidle");

    // Click the template select trigger (it has placeholder "Load from template...")
    await page.getByText("Load from template...").click();

    // Wait for dropdown to appear and click the template option
    await page
      .getByRole("option", { name: "Standard Renovation" })
      .click();

    // The first line item description should now contain "Site prep"
    // The template replaces the default empty row — the confirm dialog may or
    // may not appear depending on whether the default row has a description.
    // Default row has empty description, so applyTemplate should fire directly.
    await expect(
      page.locator('input[name="line_items.0.description"]')
    ).toHaveValue("Site prep");
  });

  // =========================================================================
  // Send Quote + PDF Tests
  // =========================================================================

  test("send quote: confirmation dialog and status update", async ({
    page,
  }) => {
    let sendIntercepted = false;

    const routes = setupProxyRoutes(page, {
      singleQuote: MOCK_QUOTE_DRAFT,
    });
    await routes.setup();

    // Add a secondary route listener to track the send POST
    await page.route("**/api/proxy**", async (route) => {
      const url = new URL(route.request().url());
      const path = url.searchParams.get("path") || "";
      if (route.request().method() === "POST" && path.includes("/send")) {
        sendIntercepted = true;
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            ...MOCK_QUOTE_DRAFT,
            status: "sent",
            sent_at: "2026-03-18T10:00:00Z",
          }),
        });
      } else {
        await route.fallback();
      }
    });

    await page.goto("/quotes/aabbcc-1111-2222-3333-444455556666");
    await page.waitForLoadState("networkidle");

    // Click "Send Quote" button (in the sidebar actions)
    await page.getByRole("button", { name: "Send Quote" }).first().click();

    // Dialog should appear with client name
    await expect(
      page.getByText("Send quote to John Smith?")
    ).toBeVisible();

    // Click the "Send Quote" button inside the dialog
    // The dialog footer has both "Cancel" and "Send Quote"
    await page
      .locator('[role="dialog"]')
      .getByRole("button", { name: "Send Quote" })
      .click();

    // Verify the POST was intercepted
    await page.waitForTimeout(500);
    expect(sendIntercepted).toBe(true);
  });

  test("quote pdf: download triggers file save", async ({ page }) => {
    let pdfEndpointCalled = false;

    const routes = setupProxyRoutes(page, {
      singleQuote: MOCK_QUOTE_DRAFT,
      pdfResponse: true,
    });
    await routes.setup();

    // Add a secondary route to track the PDF fetch specifically
    await page.route("**/api/proxy**", async (route) => {
      const url = new URL(route.request().url());
      const path = url.searchParams.get("path") || "";
      if (path.includes("/pdf")) {
        pdfEndpointCalled = true;
      }
      await route.fallback();
    });

    await page.goto("/quotes/aabbcc-1111-2222-3333-444455556666");
    await page.waitForLoadState("networkidle");

    // Inject spy to capture the anchor element download attribute.
    // The implementation does: a = document.createElement("a"); a.download = "quote-{id}.pdf"; a.click()
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
    expect(downloadFilename).toBe(
      "quote-aabbcc-1111-2222-3333-444455556666.pdf"
    );

    // 3. Verify page did not navigate away
    await expect(page).toHaveURL(
      /\/quotes\/aabbcc-1111-2222-3333-444455556666/
    );

    // 4. Button re-enabled after download completes
    await expect(
      page.getByRole("button", { name: "Download PDF" })
    ).toBeEnabled();
  });
});
