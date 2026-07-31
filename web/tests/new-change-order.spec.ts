import { test, expect, type Page, type Route } from "@playwright/test";

// E2E for the "Create Change Order" builder: reason + target + line items →
// POST /quotes/ with a change-order payload (quote_kind, project_id,
// originating_job_id, co_target).

interface CapturedBody {
  quote_kind?: string;
  project_id?: string;
  originating_job_id?: string;
  co_target?: string;
  change_reason?: string;
  schedule_impact_days?: number;
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
      return route.fulfill({ json: { id: "co-1" } });
    }
    if (method === "GET" && path.includes("/quotes/co-1"))
      return route.fulfill({
        json: {
          id: "co-1",
          company_id: "co-1",
          job_id: null,
          quote_kind: "change_order",
          co_number: 1,
          change_reason: "Rotted subfloor",
          project_id: "proj-1",
          originating_job_id: "job-1",
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
          created_at: "2026-07-30T00:00:00Z",
          updated_at: "2026-07-30T00:00:00Z",
        },
      });
    return route.fulfill({ json: [] });
  });
}

test("builds a change-order payload from the job context", async ({ page }) => {
  const captured: { body?: CapturedBody } = {};
  await mockApi(page, captured);
  await page.goto("/quotes/new-change-order?project_id=proj-1&originating_job_id=job-1");

  await page.getByLabel("Reason for change").fill("Rotted subfloor discovered under tile");
  await page.getByLabel("Schedule impact (days)").fill("3");
  await page.getByLabel("Description").fill("Replace subfloor");
  await page.getByLabel("Unit price").fill("80");

  await page.getByRole("button", { name: "Save Draft" }).click();

  await expect(page).toHaveURL(/\/quotes\/co-1$/);
  const body = captured.body;
  expect(body).toBeDefined();
  expect(body?.quote_kind).toBe("change_order");
  expect(body?.project_id).toBe("proj-1");
  expect(body?.originating_job_id).toBe("job-1");
  expect(body?.co_target).toBe("new_job");
  expect(body?.change_reason).toBe("Rotted subfloor discovered under tile");
  expect(body?.schedule_impact_days).toBe(3);
  expect(body?.line_items).toHaveLength(1);
  expect(body?.line_items?.[0]).toMatchObject({ description: "Replace subfloor", unit_price: "80" });
});

test("blocks saving without a reason", async ({ page }) => {
  const captured: { body?: CapturedBody } = {};
  await mockApi(page, captured);
  await page.goto("/quotes/new-change-order?project_id=proj-1&originating_job_id=job-1");

  await page.getByLabel("Description").fill("Replace subfloor");
  await page.getByRole("button", { name: "Save Draft" }).click();

  await expect(page).toHaveURL(/\/quotes\/new-change-order/);
  expect(captured.body).toBeUndefined();
});
