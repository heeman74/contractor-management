"use client";

import dynamic from "next/dynamic";
import { FinancialsSkeleton } from "./_components/financials-skeleton";

/** ssr: false is required — Recharts' ResponsiveContainer measures the DOM and
 *  hydrates badly under SSR. Same shell shape as the shipped Reports page. */
const CompanyFinancialsDashboard = dynamic(
  () => import("./_components/company-financials-dashboard"),
  { ssr: false, loading: () => <FinancialsSkeleton variant="company" /> }
);

export default function FinancialsPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-normal text-gray-900">Financials</h1>
        <p className="text-sm text-muted-foreground">
          Portfolio margin and budget health.
        </p>
      </div>
      <CompanyFinancialsDashboard />
    </div>
  );
}
