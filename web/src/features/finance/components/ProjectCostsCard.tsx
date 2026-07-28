"use client";

import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatCurrency } from "@/lib/format";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { useProjectCostRollup } from "../hooks";
import { CostBreakdownSummary } from "./CostBreakdownSummary";
import { CostEntryList } from "./CostEntryList";
import { SetBudgetDialog } from "./SetBudgetDialog";

interface ProjectCostsCardProps {
  projectId: string;
  projectName: string;
}

/**
 * Aggregated view of every cost entry rolling up to this project
 * (trade-scope-anchored costs + costs on jobs whose project_id matches).
 * Cost add/edit happens from the job/trade-scope detail surfaces (D-02/D-03);
 * the project budget is managed here via SetBudgetDialog.
 */
export function ProjectCostsCard({ projectId, projectName }: ProjectCostsCardProps) {
  const { data: rollup, isLoading } = useProjectCostRollup(projectId);
  const { can } = usePermissions();
  const [budgetDialogOpen, setBudgetDialogOpen] = useState(false);

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
                  budget: rollup.budget,
                }
              : null
          }
          variant="project"
          isLoading={isLoading}
          canManageBudget={can("finance.manage")}
          onManageBudget={() => setBudgetDialogOpen(true)}
        />
        <CostEntryList entries={rollup?.entries} emptyLabel="No costs recorded yet." />
      </CardContent>
      <SetBudgetDialog
        open={budgetDialogOpen}
        onOpenChange={setBudgetDialogOpen}
        anchor={{ projectId, name: projectName }}
        budget={rollup?.budget ?? null}
      />
    </Card>
  );
}
