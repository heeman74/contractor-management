"use client";

import { use, useState } from "react";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { useCostEntriesForJob, useJobCostBreakdown } from "@/features/finance/hooks";
import { AddCostDialog } from "@/features/finance/components/AddCostDialog";
import { CostBreakdownSummary } from "@/features/finance/components/CostBreakdownSummary";
import { CostEntryList } from "@/features/finance/components/CostEntryList";
import { PageSkeleton } from "./_components/page-skeleton";
import { JobNotesCard } from "./_components/job-notes-card";
import { JobActivityCard } from "./_components/job-activity-card";
import { JobStatusCard } from "./_components/job-status-card";
import { JobDocumentsCard } from "./_components/job-documents-card";
import {
  JobDetailsCard,
  JobFinancialReferencesCard,
} from "./_components/job-details-card";
import { JobTimeTrackingCard } from "./_components/job-time-tracking-card";
import { RevertJobDialog, CancelJobDialog } from "./_components/job-dialogs";
import { useJobDetail } from "./_hooks/use-job-detail";
import { getTransitionOptions } from "./_lib/job-transitions";

export default function JobDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id: jobId } = use(params);
  const job = useJobDetail(jobId);

  const [revertOpen, setRevertOpen] = useState(false);
  const [cancelOpen, setCancelOpen] = useState(false);
  const [addCostOpen, setAddCostOpen] = useState(false);
  const { can } = usePermissions();
  const { data: costEntries } = useCostEntriesForJob(jobId);
  const {
    data: breakdown,
    isLoading: breakdownLoading,
    isError: breakdownError,
  } = useJobCostBreakdown(jobId);

  if (job.jobLoading) return <PageSkeleton />;

  if (job.jobError || !job.job) {
    return (
      <div className="rounded-xl bg-white p-8 text-center ring-1 ring-foreground/10">
        <p className="text-sm text-gray-500">
          Failed to load job details. Check your connection and try again.
        </p>
      </div>
    );
  }

  const current = job.job;
  const options = getTransitionOptions(current.status);

  function advance() {
    if (options.nextStatus) job.transitionTo(options.nextStatus);
  }

  function confirmRevert() {
    if (options.revertStatus) job.transitionTo(options.revertStatus);
    setRevertOpen(false);
  }

  function confirmCancel(reason: string) {
    job.cancelJob(reason);
    setCancelOpen(false);
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold text-gray-900 truncate">
            {current.description}
          </h1>
          <div className="mt-1 flex flex-wrap gap-2 items-center">
            <span className="inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium text-gray-700">
              {current.trade_type}
            </span>
            <span className="inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium text-gray-700">
              Priority: {current.priority}
            </span>
          </div>
        </div>
      </div>

      {/* Two-column grid */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        {/* Main column */}
        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle>Description</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm leading-relaxed text-gray-700">
                {current.description}
              </p>
            </CardContent>
          </Card>

          <JobNotesCard
            notes={job.notes}
            onAddNote={job.addNote}
            isAddingNote={job.isAddingNote}
          />

          <JobActivityCard statusHistory={job.statusHistory} />
        </div>

        {/* Sidebar column */}
        <div className="space-y-4">
          <JobStatusCard
            job={current}
            options={options}
            transitionError={job.transitionError}
            isTransitioning={job.isTransitioning}
            onAdvance={advance}
            onRevertClick={() => setRevertOpen(true)}
            onCancelClick={() => setCancelOpen(true)}
          />

          <JobDocumentsCard
            job={current}
            existingQuote={job.existingQuote}
            existingInvoice={job.existingInvoice}
            isGeneratingInvoice={job.isGeneratingInvoice}
            onGenerateInvoice={job.generateInvoice}
          />

          <JobDetailsCard job={current} />
          <JobTimeTrackingCard
            timeEntries={job.timeEntries}
            totalMinutes={job.totalMinutes}
          />
          <JobFinancialReferencesCard job={current} />

          {can("finance.view") && (
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0">
                <CardTitle>Costs</CardTitle>
                {can("finance.manage") && (
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => setAddCostOpen(true)}
                    data-testid="add-cost-button"
                  >
                    <Plus className="h-3.5 w-3.5" />
                    Add cost
                  </Button>
                )}
              </CardHeader>
              <CardContent className="space-y-4">
                <CostBreakdownSummary
                  breakdown={breakdown}
                  variant="job"
                  isLoading={breakdownLoading}
                  isError={breakdownError}
                />
                <CostEntryList entries={costEntries} />
              </CardContent>
            </Card>
          )}
        </div>
      </div>

      <AddCostDialog open={addCostOpen} onOpenChange={setAddCostOpen} jobId={jobId} />

      <RevertJobDialog
        open={revertOpen}
        onOpenChange={setRevertOpen}
        revertStatus={options.revertStatus}
        isTransitioning={job.isTransitioning}
        onConfirm={confirmRevert}
      />
      <CancelJobDialog
        open={cancelOpen}
        onOpenChange={setCancelOpen}
        isTransitioning={job.isTransitioning}
        onConfirm={confirmCancel}
      />
    </div>
  );
}
