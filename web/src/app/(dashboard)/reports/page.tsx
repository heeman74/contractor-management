"use client";

import dynamic from "next/dynamic";
import { ReportsSkeleton } from "./_components/reports-skeleton";

const ReportsDashboard = dynamic(
  () => import("./_components/reports-dashboard"),
  { ssr: false, loading: () => <ReportsSkeleton /> }
);

export default function ReportsPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-normal text-gray-900">Reports</h1>
        <p className="text-sm text-muted-foreground">Business performance overview.</p>
      </div>
      <ReportsDashboard />
    </div>
  );
}
