/**
 * Breadcrumbs derived from the URL.
 *
 * Extracted from the topbar so the rule below can be tested against the real
 * route tree. The trail is built from path segments, which means it will happily
 * link to an ancestor path that no page answers: `/settings/company` produced a
 * link to `/settings`, Next prefetched it, and it 404'd — on the page itself and
 * on the click.
 */

/** Human labels for segments whose own name does not read well. */
export const SEGMENT_LABELS: Record<string, string> = {
  jobs: "Jobs",
  schedule: "Schedule",
  quotes: "Quotes",
  invoices: "Invoices",
  clients: "Clients",
  contractors: "Contractors",
  reports: "Reports",
  requests: "Requests",
  download: "Get Mobile App",
};

/**
 * Ancestor paths that exist only to group their children. No page answers them,
 * so a crumb renders as plain text rather than a link to a 404. `*` matches any
 * single segment.
 *
 * Kept honest by a test that walks the route tree and fails when a crumb would
 * link somewhere that has no page — so adding a nested route without a parent
 * page is caught here rather than by a user clicking it.
 */
const UNLINKED_ANCESTORS: readonly (readonly string[])[] = [
  // Request detail pages hang under this; the list is not a page of its own.
  ["jobs", "requests"],
  // A project has chat and gantt views, but no overview page.
  ["projects", "*"],
];

export interface BreadcrumbSegment {
  label: string;
  href: string | null;
}

function isLinkable(segments: readonly string[]): boolean {
  return !UNLINKED_ANCESTORS.some(
    (pattern) =>
      pattern.length === segments.length &&
      pattern.every((part, index) => part === "*" || part === segments[index])
  );
}

function labelFor(segment: string): string {
  return (
    SEGMENT_LABELS[segment] ??
    segment.replace(/-/g, " ").replace(/\b\w/g, (character) => character.toUpperCase())
  );
}

export function buildBreadcrumbs(pathname: string): BreadcrumbSegment[] {
  const segments = pathname.split("/").filter(Boolean);

  if (segments.length === 0) {
    return [{ label: "Dashboard", href: null }];
  }

  const crumbs: BreadcrumbSegment[] = [{ label: "Dashboard", href: "/" }];

  segments.forEach((segment, index) => {
    const ancestor = segments.slice(0, index + 1);
    const isLast = index === segments.length - 1;
    crumbs.push({
      label: labelFor(segment),
      href: isLast || !isLinkable(ancestor) ? null : "/" + ancestor.join("/"),
    });
  });

  return crumbs;
}
