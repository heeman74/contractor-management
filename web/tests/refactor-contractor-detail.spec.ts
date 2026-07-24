import { test, expect, type Page, type Route } from "@playwright/test";

// E2E for the refactored contractor detail page (God component split into
// use-contractor-detail hook + ContractorSidebar / AssignedJobsCard /
// WeeklyScheduleCard). Confirms the derived stats (active jobs, hours this
// week, most-common trade) and the extracted sub-cards still render end-to-end.
// Follows the repo convention — mock /api/proxy, no live backend.

const CONTRACTOR_ID = "c-1";

const USERS = [
  { id: "admin-1", email: "sarah@ace.com", first_name: "Sarah", last_name: "Mitchell", phone: null, roles: ["admin"] },
  {
    id: CONTRACTOR_ID,
    email: "mike@ace.com",
    first_name: "Mike",
    last_name: "Rivera",
    phone: "555-0142",
    roles: ["contractor"],
  },
];

const JOBS = [
  { id: "job-aaaa1111", description: "Kitchen sink install", status: "scheduled", trade_type: "plumbing", client_name: "Acme HOA", created_at: "2026-07-20T00:00:00Z" },
  { id: "job-bbbb2222", description: "Water heater swap", status: "in_progress", trade_type: "plumbing", client_name: "Acme HOA", created_at: "2026-07-21T00:00:00Z" },
  { id: "job-cccc3333", description: "Deck wiring", status: "completed", trade_type: "electrical", client_name: "Rivera Homes", created_at: "2026-07-10T00:00:00Z" },
];

// Backend weekly-schedule keys are day-of-week "0"=Mon .. "6"=Sun.
// Mon 8h + Tue 45m = 8h45m -> 8.8h after rounding.
const WEEKLY_SCHEDULE = {
  "0": [
    { block_index: 0, start_time: "08:00:00", end_time: "12:00:00" },
    { block_index: 1, start_time: "13:00:00", end_time: "17:00:00" },
  ],
  "1": [{ block_index: 0, start_time: "09:00:00", end_time: "09:45:00" }],
};

async function mockApi(page: Page) {
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);

  await page.route("**/api/auth/login", async (route: Route) =>
    route.fulfill({
      json: {
        user_id: "admin-1",
        company_id: "co-1",
        email: "sarah@ace.com",
        display_name: "Sarah Mitchell",
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
      return route.fulfill({ json: { permissions: ["users.view"] } });
    if (method === "GET" && path.includes("/scheduling/schedules/"))
      return route.fulfill({ json: WEEKLY_SCHEDULE });
    if (method === "GET" && path.includes("/jobs/"))
      return route.fulfill({ json: JOBS });
    if (method === "GET" && path.includes("/users/"))
      return route.fulfill({ json: USERS });
    return route.fulfill({ json: [] });
  });
}

test.describe("refactored contractor detail page", () => {
  test("renders header, quick stats, trade, jobs, and weekly schedule", async ({ page }) => {
    await mockApi(page);
    await page.goto(`/contractors/${CONTRACTOR_ID}`);

    // Header name comes from the resolved contractor record.
    await expect(page.getByRole("heading", { name: "Mike Rivera" })).toBeVisible();

    // ContractorSidebar — QuickStatsCard: 2 active jobs, 8.8h this week.
    await expect(page.getByText("Active Jobs")).toBeVisible();
    await expect(page.getByText("2", { exact: true })).toBeVisible();
    await expect(page.getByText("Hours This Week")).toBeVisible();
    await expect(page.getByText("8.8h")).toBeVisible();

    // TradeCard — most common trade across jobs is plumbing (2 vs 1).
    await expect(page.getByText("plumbing", { exact: true })).toBeVisible();

    // ContactCard — phone from the contractor record.
    await expect(page.getByText("555-0142")).toBeVisible();

    // AssignedJobsCard — all three jobs listed.
    await expect(page.getByText("Assigned Jobs")).toBeVisible();
    await expect(page.getByText("Kitchen sink install")).toBeVisible();
    await expect(page.getByText("Water heater swap")).toBeVisible();
    await expect(page.getByText("Deck wiring")).toBeVisible();

    // WeeklyScheduleCard — configured hours, so the empty state is absent and
    // the Monday time range is shown.
    await expect(page.getByText("Weekly Schedule")).toBeVisible();
    await expect(
      page.getByText("No working hours configured.", { exact: false })
    ).toHaveCount(0);
    await expect(page.getByText("08:00–12:00, 13:00–17:00")).toBeVisible();
  });

  test("shows the empty state when the contractor has no jobs or schedule", async ({ page }) => {
    await page.context().addCookies([
      { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
    ]);
    await page.route("**/api/auth/login", async (route: Route) =>
      route.fulfill({
        json: {
          user_id: "admin-1",
          company_id: "co-1",
          email: "sarah@ace.com",
          display_name: "Sarah Mitchell",
          company_name: "Ace",
          roles: ["admin"],
        },
      })
    );
    await page.route("**/api/proxy**", async (route: Route) => {
      const path = new URL(route.request().url()).searchParams.get("path") ?? "";
      if (path.includes("/me/permissions"))
        return route.fulfill({ json: { permissions: ["users.view"] } });
      if (path.includes("/scheduling/schedules/")) return route.fulfill({ json: {} });
      if (path.includes("/jobs/")) return route.fulfill({ json: [] });
      if (path.includes("/users/")) return route.fulfill({ json: USERS });
      return route.fulfill({ json: [] });
    });

    await page.goto(`/contractors/${CONTRACTOR_ID}`);

    await expect(page.getByRole("heading", { name: "Mike Rivera" })).toBeVisible();
    await expect(
      page.getByText("No jobs currently assigned to this contractor.")
    ).toBeVisible();
    await expect(
      page.getByText("No working hours configured.", { exact: false })
    ).toBeVisible();
    // No active jobs -> Quick Stats shows 0.
    await expect(page.getByText("0h")).toBeVisible();
  });
});
