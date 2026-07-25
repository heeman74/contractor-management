import { test, expect, type Page, type Route } from "@playwright/test";

// E2E for the "New Project Quote" builder: title + field sections → POST /quotes/
// with a project-level payload (no job/scope, title, per-item field).

interface CapturedBody {
  title?: string;
  job_id?: string;
  line_items?: Array<Record<string, unknown>>;
}

async function mockApi(page: Page, captured: { body?: CapturedBody }) {
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);
  await page.route("**/api/auth/login", async (route: Route) =>
    route.fulfill({
      json: {
        user_id: "u1",
        company_id: "co-1",
        email: "sarah@ace.com",
        display_name: "Sarah",
        company_name: "Ace",
        roles: ["admin"],
      },
    })
  );
  await page.route("**/api/proxy**", async (route: Route) => {
    const req = route.request();
    const path = new URL(req.url()).searchParams.get("path") ?? "";
    const method = req.method();

    if (method === "GET" && path.includes("/me/permissions"))
      return route.fulfill({ json: { permissions: ["quotes.create"] } });
    if (method === "POST" && path.endsWith("/quotes/")) {
      captured.body = req.postDataJSON() as CapturedBody;
      return route.fulfill({ json: { id: "q-new" } });
    }
    // The redirect target /quotes/q-new fetches the quote; return a minimal one.
    if (method === "GET" && path.includes("/quotes/q-new"))
      return route.fulfill({
        json: {
          id: "q-new",
          company_id: "co-1",
          job_id: null,
          title: "Cafe Buildout",
          project_id: null,
          status: "draft",
          revision_number: 1,
          tax_rate: "0",
          discount_type: null,
          discount_value: "0",
          expiry_date: null,
          sent_at: null,
          viewed_at: null,
          approved_at: null,
          declined_at: null,
          decline_reason: null,
          decline_detail: null,
          admin_notes: null,
          line_items: [],
          subtotal: "0",
          discount_amount: "0",
          tax_amount: "0",
          total: "0",
          version: 1,
          created_at: "2026-07-25T00:00:00Z",
          updated_at: "2026-07-25T00:00:00Z",
        },
      });
    return route.fulfill({ json: [] });
  });
}

test("builds a project-level quote payload grouped by field", async ({ page }) => {
  const captured: { body?: CapturedBody } = {};
  await mockApi(page, captured);
  await page.goto("/quotes/new-project");

  await page.getByLabel("Project title").fill("Cafe Buildout");

  // First field section.
  const sections = page.getByTestId("field-section");
  await sections.nth(0).getByLabel("Field / trade").fill("Electrical");
  await sections.nth(0).getByLabel("Description").fill("Install panel");
  await sections.nth(0).getByLabel("Unit price").fill("90");

  // Add a second field section.
  await page.getByTestId("add-field-button").click();
  await sections.nth(1).getByLabel("Field / trade").fill("Plumbing");
  await sections.nth(1).getByLabel("Description").fill("Run lines");
  await sections.nth(1).getByLabel("Unit price").fill("85");

  await page.getByRole("button", { name: "Save Draft" }).click();

  // Navigated to the created quote, and the POST body was a project quote.
  await expect(page).toHaveURL(/\/quotes\/q-new$/);
  const body = captured.body;
  expect(body).toBeDefined();
  expect(body?.title).toBe("Cafe Buildout");
  expect(body?.job_id).toBeUndefined();
  const items = body?.line_items ?? [];
  expect(items).toHaveLength(2);
  expect(items[0]).toMatchObject({
    field: "Electrical",
    description: "Install panel",
    unit_price: "90",
    sort_order: 0,
  });
  expect(items[1]).toMatchObject({
    field: "Plumbing",
    description: "Run lines",
    sort_order: 1,
  });
});

test("blocks saving without a title", async ({ page }) => {
  const captured: { body?: CapturedBody } = {};
  await mockApi(page, captured);
  await page.goto("/quotes/new-project");

  const sections = page.getByTestId("field-section");
  await sections.nth(0).getByLabel("Field / trade").fill("Electrical");
  await sections.nth(0).getByLabel("Description").fill("Install panel");
  await page.getByRole("button", { name: "Save Draft" }).click();

  // No POST fired (validation blocked it) and we stay on the builder.
  await expect(page).toHaveURL(/\/quotes\/new-project$/);
  expect(captured.body).toBeUndefined();
});
