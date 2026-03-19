import { test, expect } from "@playwright/test";

// ---------------------------------------------------------------------------
// Helpers: Mock API routes
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

function setupApiMocks(
  page: import("@playwright/test").Page,
  overrides?: {
    createUserStatus?: number;
    createUserBody?: unknown;
  }
) {
  // Mock auth refresh
  page.route("**/api/auth/refresh", (route) =>
    route.fulfill({ status: 200, body: JSON.stringify({ ok: true }) })
  );

  // Mock GET users list
  page.route("**/api/proxy?path=%2Fapi%2Fv1%2Fusers%2F", (route, request) => {
    if (request.method() === "GET") {
      return route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(MOCK_USERS_LIST),
      });
    }
    // POST create user
    if (request.method() === "POST") {
      const status = overrides?.createUserStatus ?? 200;
      const body = overrides?.createUserBody ?? MOCK_CONTRACTOR;
      return route.fulfill({
        status,
        contentType: "application/json",
        body: JSON.stringify(body),
      });
    }
    return route.continue();
  });

  // Mock POST roles
  page.route("**/api/proxy?path=*%2Froles*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ ok: true }),
    })
  );

  // Mock availability (optional endpoint called by the page)
  page.route("**/api/proxy?path=%2Fapi%2Fv1%2Fscheduling%2Favailability", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([]),
    })
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe("Create Contractor Dialog", () => {
  test("Add Contractor button opens create dialog", async ({ page }) => {
    setupApiMocks(page);
    await page.goto("/contractors");

    // Click Add Contractor button
    await page.getByRole("button", { name: "Add Contractor" }).click();

    // Verify dialog appeared with form fields
    await expect(
      page.getByRole("heading", { name: "Add Contractor" })
    ).toBeVisible();
    await expect(page.getByLabel(/email/i)).toBeVisible();
    await expect(page.getByLabel(/first name/i)).toBeVisible();
    await expect(page.getByLabel(/last name/i)).toBeVisible();
    await expect(page.getByLabel(/phone/i)).toBeVisible();
    await expect(page.getByLabel(/trade type/i)).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Create Contractor" })
    ).toBeVisible();
  });

  test("Can fill and submit contractor form", async ({ page }) => {
    setupApiMocks(page);
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    // Fill required fields
    await page.getByLabel(/email/i).fill("jane@example.com");
    await page.getByLabel(/first name/i).fill("Jane");
    await page.getByLabel(/last name/i).fill("Smith");
    await page.getByLabel(/phone/i).fill("+1 555-0199");

    // Submit the form
    await page.getByRole("button", { name: "Create Contractor" }).click();

    // Wait for success toast
    await expect(page.getByText("Contractor added")).toBeVisible({
      timeout: 5000,
    });
  });

  test("Shows validation error for missing email", async ({ page }) => {
    setupApiMocks(page);
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    // Fill only name fields, leave email empty
    await page.getByLabel(/first name/i).fill("Jane");
    await page.getByLabel(/last name/i).fill("Smith");

    // Submit
    await page.getByRole("button", { name: "Create Contractor" }).click();

    // The form should show validation — either HTML5 validation prevents submit
    // or our custom error shows. Check that dialog is still open.
    await expect(
      page.getByRole("heading", { name: "Add Contractor" })
    ).toBeVisible();
  });

  test("Shows validation error for missing name", async ({ page }) => {
    setupApiMocks(page);
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    // Fill only email, leave names empty
    await page.getByLabel(/email/i).fill("jane@example.com");

    // Submit
    await page.getByRole("button", { name: "Create Contractor" }).click();

    // Dialog should remain open (HTML5 required validation or our custom error)
    await expect(
      page.getByRole("heading", { name: "Add Contractor" })
    ).toBeVisible();
  });

  test("Dialog closes on successful creation", async ({ page }) => {
    setupApiMocks(page);
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    // Verify dialog is open
    await expect(
      page.getByRole("heading", { name: "Add Contractor" })
    ).toBeVisible();

    // Fill form
    await page.getByLabel(/email/i).fill("jane@example.com");
    await page.getByLabel(/first name/i).fill("Jane");
    await page.getByLabel(/last name/i).fill("Smith");

    // Submit
    await page.getByRole("button", { name: "Create Contractor" }).click();

    // Wait for toast then verify dialog is gone
    await expect(page.getByText("Contractor added")).toBeVisible({
      timeout: 5000,
    });
    await expect(
      page.getByRole("heading", { name: "Add Contractor" })
    ).not.toBeVisible();
  });

  test("Shows API error when email already exists", async ({ page }) => {
    setupApiMocks(page, {
      createUserStatus: 409,
      createUserBody: { detail: "Email already exists" },
    });
    await page.goto("/contractors");

    await page.getByRole("button", { name: "Add Contractor" }).click();

    // Fill form
    await page.getByLabel(/email/i).fill("existing@example.com");
    await page.getByLabel(/first name/i).fill("Jane");
    await page.getByLabel(/last name/i).fill("Smith");

    // Submit
    await page.getByRole("button", { name: "Create Contractor" }).click();

    // Verify error message is shown in the dialog
    await expect(page.getByRole("alert")).toBeVisible({ timeout: 5000 });
    await expect(page.getByText("Email already exists")).toBeVisible();

    // Dialog should stay open
    await expect(
      page.getByRole("heading", { name: "Add Contractor" })
    ).toBeVisible();
  });
});
