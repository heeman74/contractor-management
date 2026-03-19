import { test, expect, Page } from "@playwright/test";

// ---------------------------------------------------------------------------
// Helpers: mock API routes used by the create-job dialog
// ---------------------------------------------------------------------------

const MOCK_CLIENTS = [
  {
    id: "c1-uuid",
    user_id: "u1-uuid",
    first_name: "Alice",
    last_name: "Smith",
    email: "alice@example.com",
    phone: null,
    tags: [],
    preferred_contractor_id: null,
    preferred_contractor_name: null,
    jobs_count: 2,
  },
  {
    id: "c2-uuid",
    user_id: "u2-uuid",
    first_name: "Bob",
    last_name: "Jones",
    email: "bob@example.com",
    phone: null,
    tags: [],
    preferred_contractor_id: null,
    preferred_contractor_name: null,
    jobs_count: 0,
  },
];

const MOCK_CONTRACTORS = [
  {
    id: "ct1-uuid",
    email: "mike@example.com",
    first_name: "Mike",
    last_name: "Builder",
    phone: null,
    roles: ["contractor"],
  },
];

const MOCK_CREATED_JOB = {
  id: "new-job-uuid",
  company_id: "comp-uuid",
  description: "Fix the kitchen sink",
  trade_type: "Plumbing",
  status: "quote",
  status_history: [],
  priority: "medium",
  client_id: null,
  client_name: null,
  contractor_id: null,
  contractor_name: null,
  purchase_order_number: null,
  external_reference: null,
  tags: [],
  notes: null,
  estimated_duration_minutes: null,
  scheduled_completion_date: null,
  gps_latitude: null,
  gps_longitude: null,
  gps_address: null,
  version: 1,
  created_at: "2026-03-19T00:00:00Z",
  updated_at: "2026-03-19T00:00:00Z",
};

async function setupApiMocks(page: Page, options?: { postShouldFail?: boolean }) {
  // Mock auth refresh
  await page.route("**/api/auth/refresh", (route) =>
    route.fulfill({ status: 200, body: "{}" })
  );

  // Mock the proxy route — inspect the `path` query param to decide what to return
  await page.route("**/api/proxy**", (route) => {
    const url = new URL(route.request().url());
    const path = url.searchParams.get("path") ?? "";
    const method = route.request().method();

    // POST /api/v1/jobs/
    if (method === "POST" && path.includes("/api/v1/jobs")) {
      if (options?.postShouldFail) {
        return route.fulfill({
          status: 422,
          contentType: "application/json",
          body: JSON.stringify({ detail: "Validation failed on server" }),
        });
      }
      return route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify(MOCK_CREATED_JOB),
      });
    }

    // GET /api/v1/crm/clients
    if (method === "GET" && path.includes("/crm/clients")) {
      return route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(MOCK_CLIENTS),
      });
    }

    // GET /api/v1/users?role=contractor
    if (method === "GET" && path.includes("/users") && path.includes("role=contractor")) {
      return route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(MOCK_CONTRACTORS),
      });
    }

    // Default: return empty array for other GET requests (jobs list, counts, etc.)
    if (method === "GET") {
      return route.fulfill({
        status: 200,
        contentType: "application/json",
        body: "[]",
      });
    }

    return route.continue();
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe("Create Job Dialog", () => {
  test("New Job button opens create dialog", async ({ page }) => {
    await setupApiMocks(page);
    await page.goto("/jobs");

    // Click the New Job button
    await page.getByTestId("new-job-button").click();

    // Verify dialog is open with the expected title
    await expect(page.getByText("Create New Job")).toBeVisible();

    // Verify form fields are present
    await expect(page.getByTestId("job-description")).toBeVisible();
    await expect(page.getByTestId("trade-type-trigger")).toBeVisible();
    await expect(page.getByTestId("priority-trigger")).toBeVisible();
    await expect(page.getByTestId("client-trigger")).toBeVisible();
    await expect(page.getByTestId("contractor-trigger")).toBeVisible();
    await expect(page.getByTestId("estimated-duration")).toBeVisible();
    await expect(page.getByTestId("job-notes")).toBeVisible();
  });

  test("Can fill and submit job creation form", async ({ page }) => {
    await setupApiMocks(page);
    await page.goto("/jobs");

    // Open dialog
    await page.getByTestId("new-job-button").click();
    await expect(page.getByText("Create New Job")).toBeVisible();

    // Fill description
    await page.getByTestId("job-description").fill("Fix the kitchen sink");

    // Select trade type — click trigger then click option
    await page.getByTestId("trade-type-trigger").click();
    await page.getByRole("option", { name: "Plumbing" }).click();

    // Submit the form
    await page.getByRole("button", { name: "Create Job" }).click();

    // Verify success toast appears
    await expect(page.getByText("Job created successfully")).toBeVisible();

    // Verify dialog closed
    await expect(page.getByText("Create New Job")).not.toBeVisible();
  });

  test("Shows validation error for empty required fields", async ({ page }) => {
    await setupApiMocks(page);
    await page.goto("/jobs");

    // Open dialog
    await page.getByTestId("new-job-button").click();
    await expect(page.getByText("Create New Job")).toBeVisible();

    // Submit empty form (no description or trade type)
    await page.getByRole("button", { name: "Create Job" }).click();

    // Verify error message for description
    await expect(page.getByTestId("form-error")).toBeVisible();
    await expect(page.getByTestId("form-error")).toHaveText(
      "Description is required"
    );

    // Fill description but leave trade type empty
    await page.getByTestId("job-description").fill("Some description");
    await page.getByRole("button", { name: "Create Job" }).click();

    // Verify error message for trade type
    await expect(page.getByTestId("form-error")).toHaveText(
      "Trade type is required"
    );
  });

  test("Dialog closes on successful creation", async ({ page }) => {
    await setupApiMocks(page);
    await page.goto("/jobs");

    // Open dialog
    await page.getByTestId("new-job-button").click();
    await expect(page.getByText("Create New Job")).toBeVisible();

    // Fill required fields
    await page.getByTestId("job-description").fill("Rewire the garage");
    await page.getByTestId("trade-type-trigger").click();
    await page.getByRole("option", { name: "Electrical" }).click();

    // Fill optional duration
    await page.getByTestId("estimated-duration").fill("90");

    // Submit
    await page.getByRole("button", { name: "Create Job" }).click();

    // Verify dialog is closed
    await expect(page.getByText("Create New Job")).not.toBeVisible();

    // Verify success toast
    await expect(page.getByText("Job created successfully")).toBeVisible();
  });

  test("Shows server error in dialog on failed creation", async ({ page }) => {
    await setupApiMocks(page, { postShouldFail: true });
    await page.goto("/jobs");

    // Open dialog
    await page.getByTestId("new-job-button").click();
    await expect(page.getByText("Create New Job")).toBeVisible();

    // Fill required fields
    await page.getByTestId("job-description").fill("Some job");
    await page.getByTestId("trade-type-trigger").click();
    await page.getByRole("option", { name: "General" }).click();

    // Submit
    await page.getByRole("button", { name: "Create Job" }).click();

    // Verify error message displayed in dialog
    await expect(page.getByTestId("form-error")).toBeVisible();
    await expect(page.getByTestId("form-error")).toHaveText(
      "Validation failed on server"
    );

    // Dialog should still be open
    await expect(page.getByText("Create New Job")).toBeVisible();
  });
});
