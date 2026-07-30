"use client";

import { useQuoteVariance } from "@/features/finance/hooks";
import { QuoteVarianceCard } from "./quote-variance-card";

interface QuoteVarianceSectionProps {
  quoteId: string;
  isApproved: boolean;
}

/**
 * The hook-owning container for the quote detail page's variance card
 * (FINAI-05, 37-RESEARCH Trap 8).
 *
 * It exists ONLY so `useQuoteVariance` is a child of `FinanceGate` rather than a
 * sibling of it: a hook called directly in `page.tsx` runs unconditionally on
 * every render whatever the gate decides, which would leave the render half of
 * the double lock worth nothing for the request half. This mirrors the shipped
 * `/financials` layering, where `project-financials-dashboard.tsx` owns every
 * hook as a child of the layout-mounted `FinanceGate`.
 */
export function QuoteVarianceSection({ quoteId, isApproved }: QuoteVarianceSectionProps) {
  const variance = useQuoteVariance(quoteId, isApproved);
  return (
    <QuoteVarianceCard
      variance={variance.data}
      isLoading={variance.isLoading}
      isError={variance.isError}
    />
  );
}
