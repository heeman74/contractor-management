"use client";

import { usePermissions } from "@/lib/hooks/usePermissions";
import { FINANCE_VIEW_PERMISSION } from "@/features/finance/types";

/** UI copy, not a permission constant — so it lives with the panel that renders it. */
export const FINANCE_DENY_MESSAGE = "You do not have permission to view financials.";

/**
 * The permission guard for every financial surface. This is the third occurrence
 * of the loading-pulse → deny-panel → children recipe in this codebase (contracts,
 * role settings), so it is extracted per CLAUDE.md DRY and mounted once at
 * `financials/layout.tsx` — one component guards both financial routes.
 *
 * The permission key is imported rather than re-typed: the gate's render branch and
 * the finance hooks' `enabled` branch must fail closed on exactly the same key.
 */
export function FinanceGate({ children }: { children: React.ReactNode }) {
  const { can, isLoading } = usePermissions();

  if (isLoading) {
    return <div className="h-64 animate-pulse rounded-xl bg-muted" />;
  }

  if (!can(FINANCE_VIEW_PERMISSION)) {
    return (
      <div
        className="rounded-xl border border-yellow-200 bg-yellow-50 px-6 py-12 text-center"
        data-testid="financials-deny-panel"
      >
        <p className="text-sm font-medium text-yellow-700">{FINANCE_DENY_MESSAGE}</p>
      </div>
    );
  }

  return <>{children}</>;
}
