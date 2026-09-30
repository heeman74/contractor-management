import { test, expect, type Page, type Route } from "@playwright/test";

/**
 * A quote's own line-item table has to wrap its descriptions too.
 *
 * The list table was fixed first, but this one was left inheriting TableCell's
 * default whitespace-nowrap — so a long line-item description widened the table
 * and scrolled instead of using the lines available to it.
 */

const RENDER_TIMEOUT = 30_000;

const LONG =
  "Demolition of existing tile, waterproof membrane, rough-in plumbing for three fixtures, and final inspection";

const IDENTITY = {
  user_id: "u-1",
  company_id: "c-1",
  email: "tester@example.com",
  display_name: "Test User",
  company_name: "Test Co",
  roles: ["admin"],
};

const QUOTE = {
  id: "q-1",
  quote_number: 1001,
  job_id: null,
  client_id: null,
  title: "Bathroom",
  status: "draft",
  total: "1500.00",
  subtotal: "1500.00",
  tax_amount: "0",
  discount_amount: "0",
  created_at: "2026-01-15T10:00:00Z",
  revision_number: 1,
  tax_rate: "0",
  discount_type: null,
  discount_value: "0",
  line_items: [
    {
      id: "li-1",
      item_type: "labor",
      description: LONG,
      quantity: "8.000",
      unit: "hours",
      unit_price: "95.00",
      sort_order: 0,
      field: null,
      ai_origin: false,
      review_state: "unreviewed",
      confidence_band: null,
      basis: null,
    },
  ],
};

async function stub(page: Page) {
  await page.route("**/api/proxy**", async (route: Route) => {
    const url = decodeURIComponent(route.request().url());
    if (url.includes("/auth/me")) return route.fulfill({ json: IDENTITY });
    if (url.includes("/quotes/q-1")) return route.fulfill({ json: QUOTE });
    return route.fulfill({ json: [] });
  });
  await page.route("**/api/auth/**", (route: Route) =>
    route.fulfill({ json: { ok: true } })
  );
}

async function descriptionCell(page: Page) {
  const cell = page.getByText(LONG.slice(0, 40), { exact: false }).first();
  await expect(cell).toBeVisible({ timeout: RENDER_TIMEOUT });
  return cell.evaluate((el) => {
    const style = getComputedStyle(el);
    return {
      whiteSpace: style.whiteSpace,
      height: Math.round(el.getBoundingClientRect().height),
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
      lineHeight: parseFloat(style.lineHeight) || 20,
    };
  });
}

test("a long line-item description wraps on a narrow screen", async ({ page }) => {
  await page.setViewportSize({ width: 820, height: 1180 });
  await stub(page);
  await page.goto("/quotes/q-1", { waitUntil: "domcontentloaded" });

  const cell = await descriptionCell(page);

  expect(cell.whiteSpace, "the cell must be allowed to wrap").not.toBe("nowrap");
  expect(
    cell.height,
    `description rendered ${cell.height}px tall — it is not wrapping`
  ).toBeGreaterThan(cell.lineHeight * 1.5);
});

test("the quote detail page does not scroll sideways on a phone", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await stub(page);
  await page.goto("/quotes/q-1", { waitUntil: "domcontentloaded" });
  await expect(
    page.getByText(LONG.slice(0, 40), { exact: false }).first()
  ).toBeVisible({ timeout: RENDER_TIMEOUT });

  const { scrollWidth, clientWidth } = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  }));

  expect(
    scrollWidth,
    `the page is ${scrollWidth - clientWidth}px wider than the viewport`
  ).toBeLessThanOrEqual(clientWidth + 1);
});
