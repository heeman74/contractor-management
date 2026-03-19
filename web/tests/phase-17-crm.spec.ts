import { test } from "@playwright/test";

test.describe("Phase 17: CRM - Clients", () => {
  test.skip("client list displays paginated clients", async ({ page: _page }) => {
    // CRM-01
  });
  test.skip("client search filters results by name", async ({ page: _page }) => {
    // CRM-01
  });
  test.skip("client detail shows job history", async ({ page: _page }) => {
    // CRM-02
  });
  test.skip(
    "client detail shows properties and sidebar info",
    async ({ page: _page }) => {
      // CRM-02
    },
  );
});

test.describe("Phase 17: CRM - Contractors", () => {
  test.skip(
    "contractor list displays with availability badges",
    async ({ page: _page }) => {
      // CONTR-01
    },
  );
  test.skip(
    "contractor profile shows assigned jobs and schedule summary",
    async ({ page: _page }) => {
      // CONTR-02
    },
  );
  test.skip(
    "schedule editor allows drag-to-paint weekly hours",
    async ({ page: _page }) => {
      // CONTR-03
    },
  );
  test.skip("schedule editor saves date overrides", async ({ page: _page }) => {
    // CONTR-04
  });
});
