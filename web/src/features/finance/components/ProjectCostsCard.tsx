"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatCurrency } from "@/lib/format";
import { useProjectCostRollup } from "../hooks";
import { CostBreakdownSummary } from "./CostBreakdownSummary";
import { CostEntryList } from "./CostEntryList";

interface ProjectCostsCardProps {
  projectId: string;
}

/**
 * Read-only aggregated view of every cost entry rolling up to this project
 * (trade-scope-anchored costs + costs on jobs whose project_id matches).
 * Add/edit happens from the job/trade-scope detail surfaces (D-02/D-03).
 */
export function ProjectCostsCard({ projectId }: ProjectCostsCardProps) {
  const { data: rollup, isLoading } = useProjectCostRollup(projectId);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Costs</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-gray-500">
            Total Spent
          </p>
          <p
            className="text-2xl font-semibold text-gray-900"
            data-testid="project-cost-total"
          >
            {isLoading ? "—" : formatCurrency(rollup?.grandTotal ?? rollup?.total ?? "0")}
          </p>
        </div>
        <CostBreakdownSummary
          breakdown={
            rollup
              ? {
                  categories: rollup.categories,
                  labor: rollup.labor,
                  laborTrackedAtJobLevel: false,
                  grandTotal: rollup.grandTotal ?? rollup.total,
                  margin: rollup.margin,
                }
              : null
          }
          variant="project"
          isLoading={isLoading}
        />
        <CostEntryList entries={rollup?.entries} emptyLabel="No costs recorded yet." />
      </CardContent>
    </Card>
  );
}
