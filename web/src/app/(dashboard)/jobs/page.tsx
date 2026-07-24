"use client";

import { Suspense, useState } from "react";
import { Plus, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { CreateJobDialog } from "./_components/create-job-dialog";
import { JobsListBody } from "./_components/jobs-list-body";
import { JobsStatusTabs } from "./_components/jobs-status-tabs";
import { ListPagination } from "@/components/shared/list-pagination";
import { useJobsListData } from "./_hooks/use-jobs-list-data";
import { DEFAULT_SORT_COLUMN, REQUESTS_TAB } from "./_lib/job-list";
import { useListTableFilters } from "@/hooks/use-list-table-filters";

// Wrapped in Suspense because useSearchParams() requires a boundary in Next.js.
export default function JobsPage() {
  return (
    <Suspense>
      <JobsPageContent />
    </Suspense>
  );
}

function JobsPageContent() {
  const filters = useListTableFilters({
    basePath: "/jobs",
    defaultSortColumn: DEFAULT_SORT_COLUMN,
  });
  const [createDialogOpen, setCreateDialogOpen] = useState(false);

  const {
    jobs,
    isJobsLoading,
    hasMorePages,
    requests,
    isRequestsLoading,
    getTabCount,
  } = useJobsListData({
    activeTab: filters.activeTab,
    page: filters.page,
    search: filters.searchQuery,
    sortColumn: filters.sortColumn,
    sortDirection: filters.sortDirection,
  });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-gray-900">Jobs</h1>
        <div className="flex items-center gap-3">
          <div className="relative w-72">
            <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 pointer-events-none" />
            <Input
              className="pl-8"
              placeholder="Search jobs..."
              value={filters.searchInput}
              onChange={filters.onSearchChange}
            />
          </div>
          <Button
            onClick={() => setCreateDialogOpen(true)}
            data-testid="new-job-button"
          >
            <Plus className="h-4 w-4" data-icon="inline-start" />
            New Job
          </Button>
        </div>
      </div>

      <CreateJobDialog
        open={createDialogOpen}
        onOpenChange={setCreateDialogOpen}
      />

      <JobsStatusTabs
        activeTab={filters.activeTab}
        onTabChange={filters.onTabChange}
        getTabCount={getTabCount}
      />

      <JobsListBody
        activeTab={filters.activeTab}
        jobs={jobs}
        isJobsLoading={isJobsLoading}
        requests={requests}
        isRequestsLoading={isRequestsLoading}
        sortColumn={filters.sortColumn}
        sortDirection={filters.sortDirection}
        onSortChange={filters.onSortChange}
      />

      {filters.activeTab !== REQUESTS_TAB && (
        <ListPagination
          page={filters.page}
          hasNextPage={hasMorePages}
          onPageChange={filters.onPageChange}
        />
      )}
    </div>
  );
}
