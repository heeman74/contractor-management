import { test, expect, type Page, type Route } from "@playwright/test";

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const MOCK_CLIENTS = [
  {
    id: "client-1",
    user_id: "user-1",
    first_name: "Alice",
    last_name: "Smith",
    email: "alice@example.com",
    phone: "555-0001",
    tags: ["vip"],
    preferred_contractor_id: null,
    preferred_contractor_name: null,
    jobs_count: 3,
  },
];

const MOCK_CREATED_USER = {
  id: "new-user-id",
  email: "jane@example.com",
  first_name: "Jane",
  last_name: "Doe",
  phone: "555-9999",
};

// ---------------------------------------------------------------------------
// Helper: set up API mocks
// ---------------------------------------------------------------------------

async function mockClientsApi(
  page: Page,
  options?: {
    userCreateError?: { status: number; detail: string };
  }
) {
  // Set auth cookie so middleware doesn't redirect to login
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);

  await page.route("**/api/proxy**", async (route: Route) => {
    const url = route.request().url();
    const method = route.request().method();
    const pathParam = new URL(url).searchParams.get("path") ?? "";

    // GET /crm/clients — client list
    if (method === "GET" && pathParam.includes("/crm/clients")) {
      await route.fulfill({ json: MOCK_CLIENTS });
      return;
    }

    // POST /users/ — create user
    if (method === "POST" && pathParam.match(/\/users\/?$/) && !pathParam.includes("/roles")) {
      if (options?.userCreateError) {
        await route.fulfill({
          status: options.userCreateError.status,
          json: { detail: options.userCreateError.detail },
        });
        return;
      }
      await route.fulfill({ json: MOCK_CREATED_USER });
      return;
    }

    // POST /clients/*/profile — create client profile
    if (method === "POST" && pathParam.includes("/profile")) {
      await route.fulfill({ json: { ok: true } });
      return;
    }

    // POST /users/*/roles — assign role
    if (method === "POST" && pathParam.includes("/roles")) {
      await route.fulfill({ json: { ok: true } });
      return;
    }

    // Fallback
    await route.fulfill({ json: {} });
  });

  await page.route("**/api/auth/refresh", async (route: Route) => {
    await route.fulfill({ status: 200, json: { ok: true } });
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe("Create Client Dialog", () => {
  test.beforeEach(async ({ page }) => {
    // Set access_token cookie so middleware doesn't redirect to /login
    await page.context().addCookies([
      {
        name: "access_token",
        value: "mock-jwt-token",
        domain: "localhost",
        path: "/",
      },
    ]);
  });

  test("New Client button opens create dialog", async ({ page }) => {
    await mockClientsApi(page);
    await page.goto("/clients");

    // Verify page loaded
    await expect(page.getByRole("heading", { name: "Clients" })).toBeVisible();

    // Click New Client button
    await page.getByRole("button", { name: "New Client" }).click();

    // Verify dialog is open with form fields
    await expect(page.getByRole("heading", { name: "Create Client" })).toBeVisible();
    await expect(page.getByLabel("Email *")).toBeVisible();
    await expect(page.getByLabel("First Name *")).toBeVisible();
    await expect(page.getByLabel("Last Name *")).toBeVisible();
    await expect(page.getByLabel("Phone")).toBeVisible();
    await expect(page.getByLabel("Billing Address")).toBeVisible();
    await expect(page.getByLabel("Tags")).toBeVisible();
    await expect(page.getByLabel("Admin Notes")).toBeVisible();
    await expect(page.getByRole("button", { name: "Create Client" })).toBeVisible();
  });

  test("Can fill and submit client creation form", async ({ page }) => {
    await mockClientsApi(page);
    await page.goto("/clients");

    await page.getByRole("button", { name: "New Client" }).click();
    await expect(page.getByRole("heading", { name: "Create Client" })).toBeVisible();

    // Fill all fields
    await page.getByLabel("Email *").fill("jane@example.com");
    await page.getByLabel("First Name *").fill("Jane");
    await page.getByLabel("Last Name *").fill("Doe");
    await page.getByLabel("Phone").fill("555-9999");
    await page.getByLabel("Billing Address").fill("123 Main St, Springfield, IL 62701");
    await page.getByLabel("Tags").fill("vip, commercial");
    await page.getByLabel("Admin Notes").fill("Priority client");

    // Submit
    await page.getByRole("button", { name: "Create Client" }).click();

    // Verify success toast
    await expect(page.getByText("Client created")).toBeVisible();

    // Verify dialog closed
    await expect(page.getByRole("heading", { name: "Create Client" })).not.toBeVisible();
  });

  test("Shows validation error for missing email", async ({ page }) => {
    await mockClientsApi(page);
    await page.goto("/clients");

    await page.getByRole("button", { name: "New Client" }).click();
    await expect(page.getByRole("heading", { name: "Create Client" })).toBeVisible();

    // Fill name but leave email empty
    await page.getByLabel("First Name *").fill("Jane");
    await page.getByLabel("Last Name *").fill("Doe");

    // Submit
    await page.getByRole("button", { name: "Create Client" }).click();

    // Verify validation error
    await expect(page.getByText("Email is required")).toBeVisible();

    // Dialog should still be open
    await expect(page.getByRole("heading", { name: "Create Client" })).toBeVisible();
  });

  test("Shows validation error for missing name", async ({ page }) => {
    await mockClientsApi(page);
    await page.goto("/clients");

    await page.getByRole("button", { name: "New Client" }).click();
    await expect(page.getByRole("heading", { name: "Create Client" })).toBeVisible();

    // Fill email but leave names empty
    await page.getByLabel("Email *").fill("jane@example.com");

    // Submit
    await page.getByRole("button", { name: "Create Client" }).click();

    // Verify validation errors for both names
    await expect(page.getByText("First name is required")).toBeVisible();
    await expect(page.getByText("Last name is required")).toBeVisible();

    // Dialog should still be open
    await expect(page.getByRole("heading", { name: "Create Client" })).toBeVisible();
  });

  test("Dialog closes on successful creation", async ({ page }) => {
    await mockClientsApi(page);
    await page.goto("/clients");

    await page.getByRole("button", { name: "New Client" }).click();
    await expect(page.getByRole("heading", { name: "Create Client" })).toBeVisible();

    // Fill required fields only
    await page.getByLabel("Email *").fill("jane@example.com");
    await page.getByLabel("First Name *").fill("Jane");
    await page.getByLabel("Last Name *").fill("Doe");

    // Submit
    await page.getByRole("button", { name: "Create Client" }).click();

    // Wait for success toast
    await expect(page.getByText("Client created")).toBeVisible();

    // Dialog should be closed
    await expect(page.getByRole("heading", { name: "Create Client" })).not.toBeVisible();

    // Form fields should not be visible
    await expect(page.getByLabel("Email *")).not.toBeVisible();
  });

  test("Shows API error when email already exists", async ({ page }) => {
    await mockClientsApi(page, {
      userCreateError: { status: 409, detail: "Email already exists" },
    });
    await page.goto("/clients");

    // Wait for page to fully load
    await expect(page.getByRole("heading", { name: "Clients" })).toBeVisible();

    await page.getByRole("button", { name: "New Client" }).click();
    await expect(
      page.getByRole("heading", { name: "Create Client" })
    ).toBeVisible({ timeout: 10000 });

    // Fill required fields
    await page.getByLabel("Email *").fill("existing@example.com");
    await page.getByLabel("First Name *").fill("Existing");
    await page.getByLabel("Last Name *").fill("User");

    // Submit
    await page.getByRole("button", { name: "Create Client" }).click();

    // Verify error toast
    await expect(page.getByText("Email already exists")).toBeVisible();
  });
});
