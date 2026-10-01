/**
 * @jest-environment node
 */
/**
 * Every breadcrumb link must land on a page.
 *
 * The trail is derived from path segments, so it will link an ancestor path
 * whether or not anything answers it. `/settings/company` linked to `/settings`,
 * which had no page: Next prefetched it on arrival and it 404'd, and so did
 * clicking it. Two more were dead the same way — `/jobs/requests` and a
 * project's own path, which only has chat and gantt views beneath it.
 *
 * So this walks the real route tree rather than asserting a fixed list, and
 * fails when a nested route is added without a page at its parent. The route
 * set is the source of truth; the breadcrumb rule has to agree with it.
 */
import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";

import { buildBreadcrumbs } from "../breadcrumbs";

// Breadcrumbs come from the topbar, which renders only inside the dashboard
// shell — so these are the routes whose trails a user ever sees. Public pages
// like /sign/[token] have no topbar, and asserting on them would be testing a
// combination that does not occur.
const APP_DIR = join(__dirname, "..", "..", "..", "app", "(dashboard)");

/** Route paths that have a page, with dynamic segments left as `[param]`. */
function collectRoutes(dir: string, segments: string[] = []): string[] {
  const routes: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (entry === "page.tsx") {
      routes.push("/" + segments.join("/"));
      continue;
    }
    if (!statSync(full).isDirectory()) continue;
    // Route groups "(dashboard)" and private folders "_components" do not
    // contribute a URL segment.
    const nested =
      entry.startsWith("(") || entry.startsWith("_") ? segments : [...segments, entry];
    routes.push(...collectRoutes(full, nested));
  }
  return routes;
}

const ROUTES = collectRoutes(APP_DIR);

/** A concrete URL for a route, with sample values for dynamic segments. */
function concreteUrl(route: string): string {
  return route
    .split("/")
    .map((segment) => (segment.startsWith("[") ? "sample-id" : segment))
    .join("/");
}

function routeExistsFor(href: string): boolean {
  const hrefSegments = href.split("/").filter(Boolean);
  return ROUTES.some((route) => {
    const routeSegments = route.split("/").filter(Boolean);
    if (routeSegments.length !== hrefSegments.length) return false;
    return routeSegments.every(
      (segment, index) => segment.startsWith("[") || segment === hrefSegments[index]
    );
  });
}

it("finds the route tree, so the rest of this file means something", () => {
  expect(ROUTES.length).toBeGreaterThan(20);
  expect(ROUTES).toContain("/settings/company");
  expect(ROUTES).toContain("/settings");
});

it.each(ROUTES.map((route) => [route]))(
  "links only to real pages from %s",
  (route: string) => {
    const dead = buildBreadcrumbs(concreteUrl(route))
      .map((crumb) => crumb.href)
      .filter((href): href is string => href !== null)
      .filter((href) => !routeExistsFor(href));

    expect(dead).toEqual([]);
  }
);

it("still links the ancestors that do have pages", () => {
  // The fix must not be "stop linking anything": the trail is how you get back.
  const crumbs = buildBreadcrumbs("/jobs/sample-id");

  expect(crumbs.map((crumb) => crumb.href)).toEqual(["/", "/jobs", null]);
});

it("leaves the current page unlinked", () => {
  const crumbs = buildBreadcrumbs("/settings/company");

  expect(crumbs[crumbs.length - 1].href).toBeNull();
  expect(crumbs.map((crumb) => crumb.label)).toEqual([
    "Dashboard",
    "Settings",
    "Company",
  ]);
});

it("renders the dashboard on its own", () => {
  expect(buildBreadcrumbs("/")).toEqual([{ label: "Dashboard", href: null }]);
});
