import { test, expect, type Page, type Route } from "@playwright/test";

// ---------------------------------------------------------------------------
// Phase 21 AI Interview Playwright E2E Tests
// ---------------------------------------------------------------------------
// Tests for the /projects/[id]/interview/[scopeId] page:
//   - Empty state with "Let's build your task plan" heading
//   - SSE streaming → AI bubble updates
//   - Task preview after create_task tool_call events (AI-03)
//   - Accept Plan saves and navigates
//   - Restart Interview shows confirmation dialog
//   - Keep Current Plan dismisses dialog
//
// Mocking strategy:
//   - /api/ai-chat?path=...interview/start → returns conversation JSON
//   - /api/ai-chat?path=...interview/message → returns text/event-stream SSE
//   - /api/ai-chat?path=...interview/complete → returns task_ids
//   - ChatInput submits on Enter key press to avoid DevTools overlay
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// SSE helper
// ---------------------------------------------------------------------------

function buildSSEBody(
  events: Array<{ event: string; data: unknown }>
): string {
  return events
    .map((e) => `event: ${e.event}\ndata: ${JSON.stringify(e.data)}\n\n`)
    .join("");
}

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const MOCK_PROJECT_ID = "proj-001";
const MOCK_SCOPE_ID = "scope-electrical-001";
const MOCK_CONV_ID = "conv-interview-001";

const MOCK_CONVERSATION = {
  id: MOCK_CONV_ID,
  company_id: "co-001",
  project_id: MOCK_PROJECT_ID,
  scope_id: MOCK_SCOPE_ID,
  user_id: "user-001",
  conv_type: "interview",
  status: "active",
  version: 1,
  created_at: "2026-03-23T00:00:00Z",
  updated_at: "2026-03-23T00:00:00Z",
};

// ---------------------------------------------------------------------------
// Auth and mock helpers
// ---------------------------------------------------------------------------

async function setAuth(page: Page): Promise<void> {
  await page.context().addCookies([
    {
      name: "access_token",
      value: "mock-token",
      domain: "localhost",
      path: "/",
    },
  ]);
}

async function mockAuthRoutes(page: Page): Promise<void> {
  await page.route("**/api/auth/**", async (route: Route) => {
    await route.fulfill({ status: 200, json: { ok: true } });
  });
}

async function mockProxyRoutes(page: Page): Promise<void> {
  await page.route("**/api/proxy*", async (route: Route) => {
    const url = route.request().url();
    const pathParam = new URL(url).searchParams.get("path") ?? "";

    if (pathParam === `/api/v1/projects/${MOCK_PROJECT_ID}`) {
      await route.fulfill({
        json: {
          id: MOCK_PROJECT_ID,
          name: "Kitchen Renovation",
          status: "active",
          trade_scopes: [],
          created_at: "2026-03-23T00:00:00Z",
          updated_at: "2026-03-23T00:00:00Z",
        },
      });
    } else {
      await route.fulfill({ json: {} });
    }
  });
}

async function mockInterviewFull(
  page: Page,
  messageEvents: Array<{ event: string; data: unknown }>
): Promise<void> {
  await page.route("**/api/ai-chat**", async (route: Route) => {
    const url = route.request().url();
    const pathParam = new URL(url).searchParams.get("path") ?? "";
    const method = route.request().method();

    if (pathParam.includes("/api/v1/ai/interview/start")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(MOCK_CONVERSATION),
      });
    } else if (
      method === "POST" &&
      pathParam.includes("/api/v1/ai/interview/message")
    ) {
      const body = buildSSEBody(messageEvents);
      await route.fulfill({
        status: 200,
        headers: {
          "Content-Type": "text/event-stream; charset=utf-8",
          "Cache-Control": "no-cache",
        },
        body,
      });
    } else if (
      method === "POST" &&
      pathParam.includes("/api/v1/ai/interview/complete")
    ) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          task_ids: ["task-new-001", "task-new-002", "task-new-003"],
        }),
      });
    } else {
      await route.fulfill({ json: {} });
    }
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe("Phase 21: AI Interview Page", () => {
  // -----------------------------------------------------------------------
  // Test 1: Empty state
  // -----------------------------------------------------------------------
  test("interview page loads with empty state", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockInterviewFull(page, []);

    await page.goto(
      `/projects/${MOCK_PROJECT_ID}/interview/${MOCK_SCOPE_ID}`
    );

    await expect(page.getByText("Let's build your task plan")).toBeVisible({
      timeout: 10_000,
    });
  });

  // -----------------------------------------------------------------------
  // Test 2: SSE streaming — AI bubble shows tokens
  // -----------------------------------------------------------------------
  test("interview streaming: AI bubble updates with streamed tokens", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockInterviewFull(page, [
      { event: "token", data: { delta: "Tell me about your" } },
      { event: "token", data: { delta: " electrical work." } },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto(
      `/projects/${MOCK_PROJECT_ID}/interview/${MOCK_SCOPE_ID}`
    );
    await expect(page.getByText("Let's build your task plan")).toBeVisible({
      timeout: 10_000,
    });

    const chatInput = page.getByRole("textbox");
    await chatInput.fill("I need to install 20 outlets");
    await chatInput.press("Enter");

    await expect(
      page.getByText("Tell me about your electrical work.")
    ).toBeVisible({ timeout: 10_000 });
  });

  // -----------------------------------------------------------------------
  // Test 3: Task preview — task cards appear after create_task tool_calls
  // -----------------------------------------------------------------------
  test("task preview appears after create_task tool_call events", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockInterviewFull(page, [
      { event: "token", data: { delta: "Here are your tasks:" } },
      {
        event: "tool_call",
        data: {
          tool: "create_task",
          input: {
            title: "Install main panel",
            estimated_hours: 4.0,
            priority: "high",
            sort_order: 0,
          },
          id: "tc-001",
        },
      },
      {
        event: "tool_call",
        data: {
          tool: "create_task",
          input: {
            title: "Run conduit to outlets",
            estimated_hours: 8.0,
            priority: "medium",
            sort_order: 1,
          },
          id: "tc-002",
        },
      },
      {
        event: "tool_call",
        data: {
          tool: "create_task",
          input: {
            title: "Install outlets and covers",
            estimated_hours: 6.0,
            priority: "medium",
            sort_order: 2,
          },
          id: "tc-003",
        },
      },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto(
      `/projects/${MOCK_PROJECT_ID}/interview/${MOCK_SCOPE_ID}`
    );
    await expect(page.getByText("Let's build your task plan")).toBeVisible({
      timeout: 10_000,
    });

    const chatInput = page.getByRole("textbox");
    await chatInput.fill("I need to wire 20 outlets");
    await chatInput.press("Enter");

    // Task cards should appear — titles are in <input> elements.
    // The task preview header shows "N tasks for this trade"
    // and Accept Plan button becomes visible.
    await expect(page.getByRole("button", { name: "Accept Plan" })).toBeVisible({
      timeout: 10_000,
    });
    // Verify task title inputs (Playwright: check input value via locator)
    await expect(
      page.locator('input[placeholder="Task title"]').first()
    ).toBeVisible({ timeout: 5_000 });
    // Check that at least 3 task input fields exist (one per task)
    await expect(page.locator('input[placeholder="Task title"]')).toHaveCount(3, {
      timeout: 5_000,
    });
  });

  // -----------------------------------------------------------------------
  // Test 4: Accept Plan saves tasks and navigates
  // -----------------------------------------------------------------------
  test("accept plan saves tasks and navigates to project page", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockProxyRoutes(page);
    await mockInterviewFull(page, [
      { event: "token", data: { delta: "Here are your tasks:" } },
      {
        event: "tool_call",
        data: {
          tool: "create_task",
          input: {
            title: "Install main panel",
            estimated_hours: 4.0,
            priority: "high",
            sort_order: 0,
          },
          id: "tc-001",
        },
      },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto(
      `/projects/${MOCK_PROJECT_ID}/interview/${MOCK_SCOPE_ID}`
    );
    await expect(page.getByText("Let's build your task plan")).toBeVisible({
      timeout: 10_000,
    });

    const chatInput = page.getByRole("textbox");
    await chatInput.fill("I need to install a panel");
    await chatInput.press("Enter");

    // Wait for Accept Plan to appear
    await expect(
      page.getByRole("button", { name: "Accept Plan" })
    ).toBeVisible({ timeout: 10_000 });

    // Click Accept Plan (use force to bypass DevTools overlay)
    await page.getByRole("button", { name: "Accept Plan" }).click({ force: true });

    // Should navigate back to project detail
    await expect(page).toHaveURL(`/projects/${MOCK_PROJECT_ID}`, {
      timeout: 10_000,
    });
  });

  // -----------------------------------------------------------------------
  // Test 5: Restart Interview shows confirmation dialog
  // -----------------------------------------------------------------------
  test("restart interview shows confirmation dialog", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockInterviewFull(page, [
      { event: "token", data: { delta: "Here are your tasks:" } },
      {
        event: "tool_call",
        data: {
          tool: "create_task",
          input: { title: "Install main panel", sort_order: 0 },
          id: "tc-001",
        },
      },
      {
        event: "tool_call",
        data: {
          tool: "create_task",
          input: { title: "Run conduit", sort_order: 1 },
          id: "tc-002",
        },
      },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto(
      `/projects/${MOCK_PROJECT_ID}/interview/${MOCK_SCOPE_ID}`
    );
    await expect(page.getByText("Let's build your task plan")).toBeVisible({
      timeout: 10_000,
    });

    const chatInput = page.getByRole("textbox");
    await chatInput.fill("I need to install a panel");
    await chatInput.press("Enter");

    // Wait for Restart Interview button (inside TaskPreviewList)
    await expect(
      page.getByRole("button", { name: "Restart Interview" })
    ).toBeVisible({ timeout: 10_000 });

    // Click Restart Interview (use force to bypass DevTools overlay)
    await page.getByRole("button", { name: "Restart Interview" }).click({ force: true });

    // Confirmation dialog with destructive content should appear
    await expect(page.getByRole("dialog")).toBeVisible({ timeout: 5_000 });
    await expect(
      page.getByText("This will replace all", { exact: false })
    ).toBeVisible();
  });

  // -----------------------------------------------------------------------
  // Test 6: Keep Current Plan dismisses dialog without restarting
  // -----------------------------------------------------------------------
  test("keep current plan dismisses dialog", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockInterviewFull(page, [
      { event: "token", data: { delta: "Here are your tasks:" } },
      {
        event: "tool_call",
        data: {
          tool: "create_task",
          input: { title: "Install main panel", sort_order: 0 },
          id: "tc-001",
        },
      },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto(
      `/projects/${MOCK_PROJECT_ID}/interview/${MOCK_SCOPE_ID}`
    );
    await expect(page.getByText("Let's build your task plan")).toBeVisible({
      timeout: 10_000,
    });

    const chatInput = page.getByRole("textbox");
    await chatInput.fill("I need to install a panel");
    await chatInput.press("Enter");

    // Wait for Restart Interview
    await expect(
      page.getByRole("button", { name: "Restart Interview" })
    ).toBeVisible({ timeout: 10_000 });

    // Click Restart Interview to open dialog
    await page.getByRole("button", { name: "Restart Interview" }).click({ force: true });
    await expect(page.getByRole("dialog")).toBeVisible({ timeout: 5_000 });

    // Click "Keep Current Plan" to dismiss
    await page.getByRole("button", { name: "Keep Current Plan" }).click({ force: true });

    // Dialog should be gone, tasks still present (title in <input> element)
    await expect(page.getByRole("dialog")).not.toBeVisible({ timeout: 3_000 });
    await expect(page.locator('input[placeholder="Task title"]')).toBeVisible();
  });
});
