import type { Job, JobRequestResponse } from "@/types/api";
import {
  ALL_TAB,
  REQUESTS_TAB,
  type SortColumn,
  type SortDirection,
} from "../_lib/job-list";
import { ListEmptyState } from "@/components/shared/list-empty-state";
import { TableSkeleton } from "@/components/shared/table-skeleton";
import { JobRequestsTable } from "./job-requests-table";
import { JobsTable } from "./jobs-table";

interface JobsListBodyProps {
  activeTab: string;
  jobs: Job[];
  isJobsLoading: boolean;
  requests: JobRequestResponse[] | undefined;
  isRequestsLoading: boolean;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  onSortChange: (column: SortColumn) => void;
}

const JOBS_SKELETON_WIDTHS = ["w-32", "w-16", "w-24"];

function humanizeStatus(tab: string): string {
  return tab.replace(/_/g, " ");
}

function RequestsSection({
  requests,
  isRequestsLoading,
}: {
  requests: JobRequestResponse[] | undefined;
  isRequestsLoading: boolean;
}) {
  if (isRequestsLoading) return <TableSkeleton columnWidths={JOBS_SKELETON_WIDTHS} />;
  if (!requests || requests.length === 0) {
    return (
      <ListEmptyState
        title="No pending requests"
        message="New job requests from clients will appear here..."
      />
    );
  }
  return <JobRequestsTable requests={requests} />;
}

function JobsSection({
  activeTab,
  jobs,
  isJobsLoading,
  sortColumn,
  sortDirection,
  onSortChange,
}: Omit<JobsListBodyProps, "requests" | "isRequestsLoading">) {
  if (isJobsLoading) return <TableSkeleton columnWidths={JOBS_SKELETON_WIDTHS} />;
  if (jobs.length === 0) {
    const isAllTab = activeTab === ALL_TAB;
    return (
      <ListEmptyState
        title={isAllTab ? "No jobs found" : `No ${humanizeStatus(activeTab)} jobs`}
        message={
          isAllTab
            ? "No jobs match your current filters..."
            : `There are no jobs with ${humanizeStatus(activeTab)} status...`
        }
      />
    );
  }
  return (
    <JobsTable
      jobs={jobs}
      sortColumn={sortColumn}
      sortDirection={sortDirection}
      onSortChange={onSortChange}
    />
  );
}

export function JobsListBody({
  activeTab,
  jobs,
  isJobsLoading,
  requests,
  isRequestsLoading,
  sortColumn,
  sortDirection,
  onSortChange,
}: JobsListBodyProps) {
  const isRequestsTab = activeTab === REQUESTS_TAB;
  return (
    <div className="rounded-xl bg-white ring-1 ring-foreground/10 overflow-hidden">
      {isRequestsTab ? (
        <RequestsSection
          requests={requests}
          isRequestsLoading={isRequestsLoading}
        />
      ) : (
        <JobsSection
          activeTab={activeTab}
          jobs={jobs}
          isJobsLoading={isJobsLoading}
          sortColumn={sortColumn}
          sortDirection={sortDirection}
          onSortChange={onSortChange}
        />
      )}
    </div>
  );
}
