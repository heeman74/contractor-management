import { FinanceGate } from "@/features/finance/components/FinanceGate";

/**
 * One mount guards both `/financials` and `/financials/[projectId]`.
 *
 * Gating the render is only half the guard: every financial hook additionally
 * passes `enabled: can(FINANCE_VIEW_PERMISSION)`. Render-only gating would still
 * issue the request, so an unauthorized visit would leak money data over the wire
 * and the "zero /api/v1/financials/* requests" assertion would prove nothing.
 */
export default function FinancialsLayout({ children }: { children: React.ReactNode }) {
  return <FinanceGate>{children}</FinanceGate>;
}
