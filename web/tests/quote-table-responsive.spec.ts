import { test, expect, type Page, type Route } from "@playwright/test";

/**
 * The quotes table has to follow the viewport, and a long description has to
 * wrap rather than be clipped.
 *
 * The description column used to be `truncate max-w-[160px]` — a hard 160px with
 * an ellipsis, the same on a phone and on a 2560px monitor. TableCell is also
 * whitespace-nowrap by default, so wrapping had to be asked for explicitly.
 */

const LONG = "Full bathroom renovation including demolition, rough-in plumbing, tiling, fixtures and final inspection";

const QUOTES = [
  {
    id: "q-1",
    quote_number: 1001,
    job_id: null,
    title: LONG,
    status: "draft",
    total: "1500.00",
    created_at: "2026-01-15T10:00:00Z",
    revision_number: 1,
    tax_rate: "0",
    discount_type: null,
    discount_value: "0",
    line_items: [],
  },
];

// The dashboard shell asks who it is signed in as on mount, and renders nothing
// useful without an answer — so identity has to be stubbed, not just the lists.
const IDENTITY = {
  user_id: "u-1",
  company_id: "c-1",
  email: "tester@example.com",
  display_name: "Test User",
  company_name: "Test Co",
  roles: ["admin"],
};

async function stub(page: Page) {
  await page.route("**/api/proxy**", async (route: Route) => {
    const url = decodeURIComponent(route.request().url());
    if (url.includes("/auth/me")) return route.fulfill({ json: IDENTITY });
    if (url.includes("/quotes/")) return route.fulfill({ json: QUOTES });
    return route.fulfill({ json: [] });
  });
  await page.route("**/api/auth/**", (route: Route) => route.fulfill({ json: { ok: true } }));
}

/** Generous, because a cold dev-server compile easily exceeds the default. */
const RENDER_TIMEOUT = 30_000;

async function descriptionCell(page: Page) {
  const cell = page.locator("tbody tr td").nth(1);
  await expect(cell).toBeVisible({ timeout: RENDER_TIMEOUT });
  return cell.evaluate((el) => {
    const style = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return {
      width: Math.round(r.width),
      height: Math.round(r.height),
      whiteSpace: style.whiteSpace,
      textOverflow: style.textOverflow,
      lineHeight: parseFloat(style.lineHeight) || 20,
    };
  });
}

test("the description wraps onto several lines when the column is narrow", async ({ page }) => {
  await page.setViewportSize({ width: 820, height: 1180 });
  await stub(page);
  await page.goto("/quotes", { waitUntil: "domcontentloaded" });

  const cell = await descriptionCell(page);

  expect(cell.whiteSpace, "cell must be allowed to wrap").not.toBe("nowrap");
  expect(cell.textOverflow, "cell must not be clipped with an ellipsis").not.toBe("ellipsis");
  // A single line would be roughly one line-height tall.
  expect(
    cell.height,
    `description rendered ${cell.height}px tall — it is not wrapping`
  ).toBeGreaterThan(cell.lineHeight * 1.5);
});

test("no part of the description is hidden at any width", async ({ page }) => {
  // The column always grew with the table; what it did not do was show what it
  // held. `truncate` clipped the overflow, so the cell scrolled wider than it
  // displayed — which is the ellipsis the user actually saw.
  await stub(page);

  for (const width of [820, 1440, 2560]) {
    await page.setViewportSize({ width, height: 1000 });
    await page.goto("/quotes", { waitUntil: "domcontentloaded" });

    const cell = page.locator("tbody tr td").nth(1);
    await expect(cell).toBeVisible({ timeout: RENDER_TIMEOUT });
    const clipped = await cell.evaluate((el) => ({
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
    }));

    expect(
      clipped.scrollWidth,
      `at ${width}px the description overflows its cell by ${clipped.scrollWidth - clipped.clientWidth}px, so it is being clipped`
    ).toBeLessThanOrEqual(clipped.clientWidth + 1);
  }
});

test("the table still fits a phone without the page scrolling sideways", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await stub(page);
  await page.goto("/quotes", { waitUntil: "domcontentloaded" });
  await expect(page.locator("tbody tr td").nth(1)).toBeVisible({ timeout: RENDER_TIMEOUT });

  const { scrollWidth, clientWidth } = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  }));

  expect(scrollWidth).toBeLessThanOrEqual(clientWidth + 1);
});
