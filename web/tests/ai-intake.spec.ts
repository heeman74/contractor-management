import { test, expect, type Page, type Route } from "@playwright/test";

// ---------------------------------------------------------------------------
// Phase 21 AI Intake Playwright E2E Tests
// ---------------------------------------------------------------------------
// Tests for the /projects/new/ai-intake page:
//   - Empty state with "Tell me about your project" heading
//   - User message send → user bubble visible
//   - SSE token streaming → AI bubble updates
//   - Trade scope preview after tool_call events
//   - Clarifying question appears in chat
//   - Create Project saves and navigates
//   - Error state from SSE error event
//   - Offline banner when navigator.onLine is false
//
// Mocking strategy:
//   - /api/ai-chat?path=...intake/start → returns conversation JSON
//   - /api/ai-chat?path=...intake/message → returns text/event-stream SSE body
//   - /api/ai-chat?path=...intake/complete → returns project_id
//   - ChatInput submits on Enter key press to avoid DevTools overlay click issues
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// SSE helper — build a text/event-stream body from event objects
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

const MOCK_CONV_ID = "conv-intake-001";
const MOCK_PROJECT_ID = "proj-new-001";

const MOCK_CONVERSATION = {
  id: MOCK_CONV_ID,
  company_id: "co-001",
  project_id: null,
  scope_id: null,
  user_id: "user-001",
  conv_type: "intake",
  status: "active",
  version: 1,
  created_at: "2026-03-23T00:00:00Z",
  updated_at: "2026-03-23T00:00:00Z",
};

// ---------------------------------------------------------------------------
// Auth and route setup helpers
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
          name: "New House",
          status: "draft",
          trade_scopes: [],
          created_at: "2026-03-23T00:00:00Z",
          updated_at: "2026-03-23T00:00:00Z",
        },
      });
    } else if (pathParam === "/api/v1/projects/") {
      await route.fulfill({ json: [] });
    } else if (pathParam.includes("/api/v1/trade-catalog/")) {
      await route.fulfill({ json: [] });
    } else {
      await route.fulfill({ json: {} });
    }
  });
}

async function mockIntakeStart(page: Page): Promise<void> {
  await page.route("**/api/ai-chat**", async (route: Route) => {
    const url = route.request().url();
    const pathParam = new URL(url).searchParams.get("path") ?? "";

    if (pathParam.includes("/api/v1/ai/intake/start")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(MOCK_CONVERSATION),
      });
    } else {
      await route.fulfill({ json: {} });
    }
  });
}

async function mockIntakeFull(
  page: Page,
  events: Array<{ event: string; data: unknown }>
): Promise<void> {
  await page.route("**/api/ai-chat**", async (route: Route) => {
    const url = route.request().url();
    const pathParam = new URL(url).searchParams.get("path") ?? "";
    const method = route.request().method();

    if (pathParam.includes("/api/v1/ai/intake/start")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(MOCK_CONVERSATION),
      });
    } else if (
      method === "POST" &&
      pathParam.includes("/api/v1/ai/intake/message")
    ) {
      const body = buildSSEBody(events);
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
      pathParam.includes("/api/v1/ai/intake/complete")
    ) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          project_id: MOCK_PROJECT_ID,
          trade_scope_ids: ["scope-001", "scope-002"],
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

test.describe("Phase 21: AI Intake Page", () => {
  // -----------------------------------------------------------------------
  // Test 1: Empty state
  // -----------------------------------------------------------------------
  test("intake page loads with empty state", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockIntakeStart(page);

    await page.goto("/projects/new/ai-intake");

    await expect(page.getByText("Tell me about your project")).toBeVisible({
      timeout: 10_000,
    });
  });

  // -----------------------------------------------------------------------
  // Test 2: User sends message — user bubble appears
  // Uses Enter key to submit to avoid TanStack DevTools overlay interference.
  // -----------------------------------------------------------------------
  test("user can send a message and user bubble appears", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockIntakeFull(page, [
      {
        event: "token",
        data: { delta: "I'll help you plan your project." },
      },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto("/projects/new/ai-intake");
    await expect(page.getByText("Tell me about your project")).toBeVisible({
      timeout: 10_000,
    });

    // Type and submit with Enter key (ChatInput submits on Enter without Shift)
    const chatInput = page.getByRole("textbox");
    await chatInput.fill("Build a house with 3 bedrooms");
    await chatInput.press("Enter");

    // User message bubble should appear
    await expect(page.getByText("Build a house with 3 bedrooms")).toBeVisible({
      timeout: 5_000,
    });
  });

  // -----------------------------------------------------------------------
  // Test 3: SSE streaming — AI bubble appears with streamed tokens
  // -----------------------------------------------------------------------
  test("SSE streaming: AI bubble updates with each token", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockIntakeFull(page, [
      { event: "token", data: { delta: "I'll help" } },
      { event: "token", data: { delta: " you plan" } },
      { event: "token", data: { delta: " your project" } },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto("/projects/new/ai-intake");
    await expect(page.getByText("Tell me about your project")).toBeVisible({
      timeout: 10_000,
    });

    const chatInput = page.getByRole("textbox");
    await chatInput.fill("Build a house");
    await chatInput.press("Enter");

    // AI bubble should eventually show the full response
    await expect(
      page.getByText("I'll help you plan your project")
    ).toBeVisible({ timeout: 10_000 });
  });

  // -----------------------------------------------------------------------
  // Test 4: Trade scope preview after tool_call
  // -----------------------------------------------------------------------
  test("trade scope preview appears after tool_call events", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockIntakeFull(page, [
      { event: "token", data: { delta: "Generating your trade breakdown..." } },
      {
        event: "tool_call",
        data: {
          tool: "create_trade_scope",
          input: { trade_name: "Electrical", trade_color: "#3949AB", sort_order: 0 },
          id: "tc-001",
        },
      },
      {
        event: "tool_call",
        data: {
          tool: "create_trade_scope",
          input: { trade_name: "Plumbing", trade_color: "#0097A7", sort_order: 1 },
          id: "tc-002",
        },
      },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto("/projects/new/ai-intake");
    await expect(page.getByText("Tell me about your project")).toBeVisible({
      timeout: 10_000,
    });

    const chatInput = page.getByRole("textbox");
    await chatInput.fill("Build an office");
    await chatInput.press("Enter");

    // Trade scope preview card should show trade names
    await expect(page.getByText("Electrical")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByText("Plumbing")).toBeVisible({ timeout: 10_000 });

    // Create Project button should appear and be enabled
    await expect(
      page.getByRole("button", { name: "Create Project" })
    ).toBeVisible({ timeout: 5_000 });
  });

  // -----------------------------------------------------------------------
  // Test 5: Clarifying question appears in chat
  // -----------------------------------------------------------------------
  test("clarifying question appears in chat", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockIntakeFull(page, [
      {
        event: "tool_call",
        data: {
          tool: "ask_clarifying_question",
          input: { question: "How many stories is the building?" },
          id: "tc-cq-001",
        },
      },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto("/projects/new/ai-intake");
    await expect(page.getByText("Tell me about your project")).toBeVisible({
      timeout: 10_000,
    });

    const chatInput = page.getByRole("textbox");
    await chatInput.fill("Build a commercial building");
    await chatInput.press("Enter");

    // Clarifying question should appear in the AI bubble
    await expect(
      page.getByText("How many stories is the building?")
    ).toBeVisible({ timeout: 10_000 });
  });

  // -----------------------------------------------------------------------
  // Test 6: Create Project saves and navigates
  // -----------------------------------------------------------------------
  test("create project saves and navigates to project page", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockProxyRoutes(page);
    await mockIntakeFull(page, [
      { event: "token", data: { delta: "Generating trade breakdown..." } },
      {
        event: "tool_call",
        data: {
          tool: "create_trade_scope",
          input: { trade_name: "Electrical", trade_color: "#3949AB", sort_order: 0 },
          id: "tc-001",
        },
      },
      { event: "done", data: { stop_reason: "end_turn" } },
    ]);

    await page.goto("/projects/new/ai-intake");
    await expect(page.getByText("Tell me about your project")).toBeVisible({
      timeout: 10_000,
    });

    // Send a message to trigger trade scope generation
    const chatInput = page.getByRole("textbox");
    await chatInput.fill("Build a house");
    await chatInput.press("Enter");

    // Wait for Create Project button
    await expect(
      page.getByRole("button", { name: "Create Project" })
    ).toBeVisible({ timeout: 10_000 });

    // Click Create Project (use force to bypass DevTools overlay)
    await page.getByRole("button", { name: "Create Project" }).click({ force: true });

    // Should navigate to the project page
    await expect(page).toHaveURL(`/projects/${MOCK_PROJECT_ID}`, {
      timeout: 10_000,
    });
  });

  // -----------------------------------------------------------------------
  // Test 7: Offline banner shown when disconnected
  // -----------------------------------------------------------------------
  test("offline banner shows when navigator.onLine is false", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockIntakeStart(page);

    // Override navigator.onLine before page load
    await page.addInitScript(() => {
      Object.defineProperty(navigator, "onLine", {
        configurable: true,
        get: () => false,
      });
      window.addEventListener("DOMContentLoaded", () => {
        window.dispatchEvent(new Event("offline"));
      });
    });

    await page.goto("/projects/new/ai-intake");

    // ChatInput shows offline banner: "AI features require an internet connection."
    await expect(
      page.getByText("AI features require an internet connection.")
    ).toBeVisible({ timeout: 10_000 });
  });

  // -----------------------------------------------------------------------
  // Test 8: Error state shown in chat area
  // -----------------------------------------------------------------------
  test("error state shows in chat area", async ({ page }) => {
    await setAuth(page);
    await mockAuthRoutes(page);
    await mockIntakeFull(page, [
      {
        event: "error",
        data: { message: "Something went wrong. Please try again." },
      },
    ]);

    await page.goto("/projects/new/ai-intake");
    await expect(page.getByText("Tell me about your project")).toBeVisible({
      timeout: 10_000,
    });

    const chatInput = page.getByRole("textbox");
    await chatInput.fill("Build a house");
    await chatInput.press("Enter");

    // Error message should appear (may be in both the chat bubble and error banner)
    await expect(
      page.getByText("Something went wrong. Please try again.", { exact: false }).first()
    ).toBeVisible({ timeout: 10_000 });
  });
});
