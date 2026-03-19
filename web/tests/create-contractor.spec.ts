import { test, expect, type Page, type Route } from "@playwright/test";

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const MOCK_CONTRACTOR = {
  id: "new-contractor-id",
  email: "jane@example.com",
  first_name: "Jane",
  last_name: "Smith",
  phone: "+1 555-0199",
  roles: ["contractor"],
};

const MOCK_USERS_LIST = [
  {
    id: "existing-1",
    email: "bob@example.com",
    first_name: "Bob",
    last_name: "Builder",
    phone: null,
    roles: ["contractor"],
  },
];

// ---------------------------------------------------------------------------
// Helper: set up API mocks (same pattern as create-client.spec.ts)
// ---------------------------------------------------------------------------

async function mockContractorsApi(
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

    // GET /users — users list (contractors page)
    if (method === "GET" && pathParam.includes("/users")) {
      await route.fulfill({ json: MOCK_USERS_LIST });
      return;
    }

    // POST /users/ — create user (not roles)
    if (method === "POST" && pathParam.match(/\/users\/?$/) && !pathParam.includes("/roles")) {
      if (options?.userCreateError) {
        await route.fulfill({
          status: options.userCreateError.status,
          json: { detail: options.userCreateError.detail },
        });
        return;
      }
      await route.fulfill({ json: MOCK_CONTRACTOR });
      return;
    }

    // POST /users/*/roles — assign role
    if (method === "POST" && pathParam.includes("/roles")) {
      await route.fulfill({ json: { ok: true } });
      return;
    }

    // POST /scheduling/availability — contractors page calls this
    if (method === "POST" && pathParam.includes("/scheduling/availability")) {
      await route.fulfill({ json: [] });
      return;
    }

    // Fallback for any other requests
    await route.fulfill({ json: {} });
  });

  await page.route("**/api/auth/refresh", async (route: Route) => {
    await route.fulfill({ status: 200, json: { ok: true } });
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe("Create Contractor Dialog", () => {
  test("Add Contractor button opens create dialog", async ({ page }) => {
    await mockContractorsApi(page);
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    await expect(page.getByRole("heading", { name: "Add Contractor" })).toBeVisible();
    await expect(page.getByLabel(/email/i)).toBeVisible();
    await expect(page.getByLabel(/first name/i)).toBeVisible();
    await expect(page.getByLabel(/last name/i)).toBeVisible();
    await expect(page.getByLabel(/phone/i)).toBeVisible();
  });

  test("Can fill and submit contractor form", async ({ page }) => {
    await mockContractorsApi(page);
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    await page.getByLabel(/email/i).fill("jane@example.com");
    await page.getByLabel(/first name/i).fill("Jane");
    await page.getByLabel(/last name/i).fill("Smith");
    await page.getByLabel(/phone/i).fill("+1 555-0199");

    await page.getByRole("button", { name: "Create Contractor" }).click();

    await expect(page.getByText("Contractor added")).toBeVisible({ timeout: 5000 });
  });

  test("Shows validation error for missing email", async ({ page }) => {
    await mockContractorsApi(page);
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    await page.getByLabel(/first name/i).fill("Jane");
    await page.getByLabel(/last name/i).fill("Smith");

    await page.getByRole("button", { name: "Create Contractor" }).click();

    // Dialog should remain open (HTML5 required validation)
    await expect(page.getByRole("heading", { name: "Add Contractor" })).toBeVisible();
  });

  test("Shows validation error for missing name", async ({ page }) => {
    await mockContractorsApi(page);
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    await page.getByLabel(/email/i).fill("jane@example.com");

    await page.getByRole("button", { name: "Create Contractor" }).click();

    await expect(page.getByRole("heading", { name: "Add Contractor" })).toBeVisible();
  });

  test("Dialog closes on successful creation", async ({ page }) => {
    await mockContractorsApi(page);
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();
    await expect(page.getByRole("heading", { name: "Add Contractor" })).toBeVisible();

    await page.getByLabel(/email/i).fill("jane@example.com");
    await page.getByLabel(/first name/i).fill("Jane");
    await page.getByLabel(/last name/i).fill("Smith");

    await page.getByRole("button", { name: "Create Contractor" }).click();

    await expect(page.getByText("Contractor added")).toBeVisible({ timeout: 5000 });
    await expect(page.getByRole("heading", { name: "Add Contractor" })).not.toBeVisible();
  });

  test("Shows API error when email already exists", async ({ page }) => {
    await mockContractorsApi(page, {
      userCreateError: { status: 409, detail: "Email already exists" },
    });
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    await page.getByLabel(/email/i).fill("existing@example.com");
    await page.getByLabel(/first name/i).fill("Jane");
    await page.getByLabel(/last name/i).fill("Smith");

    await page.getByRole("button", { name: "Create Contractor" }).click();

    await expect(page.getByRole("alert")).toBeVisible({ timeout: 5000 });
    await expect(page.getByText("Email already exists")).toBeVisible();
    await expect(page.getByRole("heading", { name: "Add Contractor" })).toBeVisible();
  });
});
