import { test, expect, type Page, type Route } from "@playwright/test";

// ---------------------------------------------------------------------------
// Phase 28 — Web media authoring (job-notes composer) Playwright E2E
// ---------------------------------------------------------------------------
// Verifies the MediaComposer renders on the job detail notes card, the drawing
// dialog opens, and adding a note with a photo drives the two-step
// create-note → upload-attachment flow.
// ---------------------------------------------------------------------------

const JOB_ID = "job-media-001";

const MOCK_JOB = {
  id: JOB_ID,
  company_id: "co-001",
  description: "Kitchen sink repair",
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
  created_at: "2026-07-01T00:00:00Z",
  updated_at: "2026-07-01T00:00:00Z",
};

const MOCK_NOTE = {
  id: "note-001",
  job_id: JOB_ID,
  author_id: "user-0001",
  body: "On-site progress",
  attachments: [],
  created_at: "2026-07-02T00:00:00Z",
};

const MOCK_ATTACHMENT = {
  id: "att-001",
  company_id: "co-001",
  note_id: "note-001",
  attachment_type: "photo",
  remote_url: "/files/attachments/note-001/photo.png",
  caption: null,
  sort_order: 0,
  created_at: "2026-07-02T00:00:00Z",
  updated_at: "2026-07-02T00:00:00Z",
};

interface Calls {
  createdNote: boolean;
  uploaded: boolean;
}

async function setup(page: Page, calls: Calls) {
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);

  await page.route("**/api/proxy*", async (route: Route) => {
    const url = new URL(route.request().url());
    const path = url.searchParams.get("path") ?? "";
    const method = route.request().method();

    if (path === `/api/v1/jobs/${JOB_ID}` && method === "GET") {
      return route.fulfill({ json: MOCK_JOB });
    }
    if (path === `/api/v1/jobs/${JOB_ID}/notes` && method === "GET") {
      return route.fulfill({ json: [] });
    }
    if (path === `/api/v1/jobs/${JOB_ID}/notes` && method === "POST") {
      calls.createdNote = true;
      return route.fulfill({ status: 201, json: MOCK_NOTE });
    }
    if (path === "/api/v1/files/upload" && method === "POST") {
      calls.uploaded = true;
      return route.fulfill({ status: 201, json: MOCK_ATTACHMENT });
    }
    if (path === "/api/v1/me/permissions" && method === "GET") {
      return route.fulfill({ json: { permissions: ["jobs.edit"] } });
    }
    // Everything else the job page pulls (time entries, quotes, invoices, ...).
    return route.fulfill({ status: 200, json: [] });
  });

  await page.goto(`/jobs/${JOB_ID}`);
}

test.describe("Phase 28 — job notes media composer", () => {
  test("composer actions render on the notes card", async ({ page }) => {
    await setup(page, { createdNote: false, uploaded: false });

    await expect(page.getByRole("button", { name: "Photo", exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Draw", exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Annotate photo" })).toBeVisible();
  });

  test("Draw opens a canvas dialog", async ({ page }) => {
    await setup(page, { createdNote: false, uploaded: false });

    await page.getByRole("button", { name: "Draw" }).click();

    await expect(page.getByRole("dialog")).toBeVisible();
    await expect(page.getByRole("heading", { name: "Draw" })).toBeVisible();
    await expect(page.getByRole("dialog").locator("canvas")).toBeVisible();
    await expect(page.getByRole("button", { name: "Add drawing" })).toBeVisible();
  });

  test("adding a note with a photo drives note + upload calls", async ({ page }) => {
    const calls = { createdNote: false, uploaded: false };
    await setup(page, calls);

    // Stage a photo on the hidden multi-file input (the photo picker).
    await page.locator('input[type="file"][multiple]').setInputFiles({
      name: "site.png",
      mimeType: "image/png",
      buffer: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    });

    // A staged attachment thumbnail appears.
    await expect(page.getByRole("button", { name: "Remove attachment" })).toBeVisible();

    await page.getByPlaceholder("Add a note...").fill("Progress photo attached");
    await page.getByRole("button", { name: "Add Note" }).click();

    await expect.poll(() => calls.createdNote).toBe(true);
    await expect.poll(() => calls.uploaded).toBe(true);
  });
});
