import { test, expect, type Page, type Route } from "@playwright/test";

/**
 * The app must fit the screen it is on, at both ends of the range.
 *
 * Two failures this pins, both of which were live and neither of which is
 * visible without measuring:
 *
 *  - On a phone, several pages scrolled sideways. Fixed-width search fields and
 *    nowrap status tabs widened the document past the viewport.
 *  - On a wide monitor, some pages sat in a 1280px column while others used the
 *    full width, so the same app looked differently sized depending on the page.
 *
 * Reading CSS does not catch either one; the layout has to be measured.
 */

const PAGES = [
  "/",
  "/quotes",
  "/jobs",
  "/clients",
  "/contractors",
  "/team",
  "/projects",
  "/invoices",
];

const PHONE = { width: 390, height: 844 };
const WIDE = { width: 2560, height: 1440 };

/** Wide layouts should use most of the screen, not a fraction of it. */
const MIN_WIDE_USAGE = 0.8;

async function stubApi(page: Page) {
  await page.route("**/api/proxy**", async (route: Route) => {
    await route.fulfill({ json: [] });
  });
  await page.route("**/api/auth/**", async (route: Route) => {
    await route.fulfill({ json: { ok: true } });
  });
}

/** Wait for the page to have actually laid out, rather than guessing at a delay.
 *  A fixed wait flaked whenever the dev server was compiling the route cold. */
async function waitForLayout(page: Page) {
  await page.waitForFunction(() => {
    const inner = document.querySelector("main")?.firstElementChild;
    return !!inner && inner.getBoundingClientRect().width > 0;
  }, undefined, { timeout: 30_000 });
}

async function metrics(page: Page) {
  return page.evaluate(() => {
    const main = document.querySelector("main");
    const inner = main?.firstElementChild;
    return {
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
      contentWidth: inner ? inner.getBoundingClientRect().width : 0,
    };
  });
}

for (const path of PAGES) {
  test(`${path} does not scroll sideways on a phone`, async ({ page }) => {
    await page.setViewportSize(PHONE);
    await stubApi(page);
    await page.goto(path, { waitUntil: "domcontentloaded" });
    await waitForLayout(page);

    const { scrollWidth, clientWidth } = await metrics(page);

    // One pixel of slack for sub-pixel rounding; anything more is real overflow.
    expect(
      scrollWidth,
      `${path} is ${scrollWidth - clientWidth}px wider than the viewport`
    ).toBeLessThanOrEqual(clientWidth + 1);
  });

  test(`${path} uses the width of a wide screen`, async ({ page }) => {
    await page.setViewportSize(WIDE);
    await stubApi(page);
    await page.goto(path, { waitUntil: "domcontentloaded" });
    await waitForLayout(page);

    const { contentWidth, clientWidth } = await metrics(page);

    expect(
      contentWidth / clientWidth,
      `${path} used only ${Math.round((contentWidth / clientWidth) * 100)}% of a ${clientWidth}px screen`
    ).toBeGreaterThan(MIN_WIDE_USAGE);
  });
}
