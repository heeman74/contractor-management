"use client";

import dynamic from "next/dynamic";
import { useParams } from "next/navigation";

import { FinancialsSkeleton } from "../_components/financials-skeleton";

/** ssr: false is required — Recharts' ResponsiveContainer measures the DOM and
 *  hydrates badly under SSR. Same shell shape as the shipped Reports page. */
const ProjectFinancialsDashboard = dynamic(
  () => import("./_components/project-financials-dashboard"),
  { ssr: false, loading: () => <FinancialsSkeleton variant="project" /> }
);

export default function ProjectFinancialsPage() {
  const params = useParams<{ projectId: string }>();

  return (
    <div className="space-y-6">
      <ProjectFinancialsDashboard projectId={params.projectId} />
    </div>
  );
}
