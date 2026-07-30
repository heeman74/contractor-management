"use client";

import { usePermissions } from "@/lib/hooks/usePermissions";
import { FINANCE_VIEW_PERMISSION } from "@/features/finance/types";

/** UI copy, not a permission constant — so it lives with the panel that renders it. */
export const FINANCE_DENY_MESSAGE = "You do not have permission to view financials.";

function DenyPanel() {
  return (
    <div
      className="rounded-xl border border-yellow-200 bg-yellow-50 px-6 py-12 text-center"
      data-testid="financials-deny-panel"
    >
      <p className="text-sm font-medium text-yellow-700">{FINANCE_DENY_MESSAGE}</p>
    </div>
  );
}

/**
 * The permission guard for every financial surface. This is the third occurrence
 * of the loading-pulse → deny-panel → children recipe in this codebase (contracts,
 * role settings), so it is extracted per CLAUDE.md DRY and mounted once at
 * `financials/layout.tsx` — one component guards both financial routes.
 *
 * The permission key is imported rather than re-typed: the gate's render branch and
 * the finance hooks' `enabled` branch must fail closed on exactly the same key.
 *
 * `fallback` is optional and renders in place of BOTH the loading pulse and the
 * deny panel — a caller that wants no reserved space and no deny panel (a sidebar
 * card the viewer may not be entitled to on a page they otherwise own, e.g.
 * `/quotes/[id]`) passes `fallback={null}`. Omitting the prop must stay
 * byte-identical to the shipped behaviour, so both branches below discriminate
 * on the prop being present at all — a nullish-coalescing check would treat an
 * explicit `null` the same as an omitted prop and would render the pulse/deny
 * panel in a sidebar that asked for neither.
 */
export function FinanceGate({
  children,
  fallback,
}: {
  children: React.ReactNode;
  fallback?: React.ReactNode;
}) {
  const { can, isLoading } = usePermissions();

  if (isLoading) {
    return fallback !== undefined ? (
      <>{fallback}</>
    ) : (
      <div className="h-64 animate-pulse rounded-xl bg-muted" />
    );
  }

  if (!can(FINANCE_VIEW_PERMISSION)) {
    return fallback !== undefined ? <>{fallback}</> : <DenyPanel />;
  }

  return <>{children}</>;
}
