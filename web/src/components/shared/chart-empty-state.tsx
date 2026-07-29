/**
 * The two-line empty state every chart card shares. Markup is identical to the
 * local `EmptyState` in `reports-dashboard.tsx`.
 *
 * Migrating the Reports page onto this component is deliberately out of scope:
 * the Phase 30 D-06 boundary keeps Reports untouched so its shipped Playwright
 * suite stays green without being re-run against modified source. Folding it in
 * belongs to whichever phase next touches Reports.
 */
export function ChartEmptyState({ heading, body }: { heading: string; body: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-16" role="status">
      <p className="text-sm font-medium text-muted-foreground">{heading}</p>
      <p className="mt-1 text-sm text-muted-foreground">{body}</p>
    </div>
  );
}
