"use client";

import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { useQuery, useQueries } from "@tanstack/react-query";
import { Search, ArrowUpDown, ArrowUp, ArrowDown, Plus } from "lucide-react";
import { CreateJobDialog } from "./_components/create-job-dialog";
import { toast } from "sonner";
import { apiGet } from "@/lib/api-client";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { Job, JobRequestResponse, JobStatus } from "@/types/api";

const PAGE_SIZE = 25;

type SortCol = "id" | "description" | "status" | "created_at";
type SortDir = "asc" | "desc";

const STATUS_TABS: { label: string; value: string }[] = [
  { label: "All", value: "all" },
  { label: "Quote", value: "quote" },
  { label: "Scheduled", value: "scheduled" },
  { label: "In Progress", value: "in_progress" },
  { label: "Complete", value: "complete" },
  { label: "Invoiced", value: "invoiced" },
];

const JOB_STATUSES: JobStatus[] = [
  "quote",
  "scheduled",
  "in_progress",
  "complete",
  "invoiced",
];

function sortJobs(jobs: Job[], col: SortCol, dir: SortDir): Job[] {
  return [...jobs].sort((a, b) => {
    let valA: string | number = "";
    let valB: string | number = "";

    switch (col) {
      case "id":
        valA = a.id;
        valB = b.id;
        break;
      case "description":
        valA = a.description.toLowerCase();
        valB = b.description.toLowerCase();
        break;
      case "status":
        valA = a.status;
        valB = b.status;
        break;
      case "created_at":
        valA = a.created_at;
        valB = b.created_at;
        break;
    }

    if (valA < valB) return dir === "asc" ? -1 : 1;
    if (valA > valB) return dir === "asc" ? 1 : -1;
    return 0;
  });
}

// Default export wraps with Suspense boundary required by Next.js for useSearchParams()
export default function JobsPage() {
  return (
    <Suspense>
      <JobsPageContent />
    </Suspense>
  );
}

function JobsPageContent() {
  const searchParams = useSearchParams();
  const router = useRouter();

  const activeTab = searchParams.get("tab") ?? "all";
  const page = parseInt(searchParams.get("page") ?? "1", 10);
  const searchQuery = searchParams.get("q") ?? "";
  const sortCol = (searchParams.get("sort") ?? "created_at") as SortCol;
  const sortDir = (searchParams.get("dir") ?? "desc") as SortDir;

  const [searchInput, setSearchInput] = useState(searchQuery);
  const [debouncedSearch, setDebouncedSearch] = useState(searchQuery);
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Keep searchInput in sync with URL param on initial load / back-nav
  useEffect(() => {
    setSearchInput(searchQuery);
    setDebouncedSearch(searchQuery);
  }, [searchQuery]);

  const handleSearchChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const value = e.target.value;
      setSearchInput(value);

      if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = setTimeout(() => {
        setDebouncedSearch(value);
        // Update URL params
        const params = new URLSearchParams(searchParams.toString());
        if (value) {
          params.set("q", value);
        } else {
          params.delete("q");
        }
        params.set("page", "1");
        router.replace(`/jobs?${params.toString()}`);
      }, 300);
    },
    [router, searchParams]
  );

  const handleTabChange = useCallback(
    (tab: string) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set("tab", tab);
      params.set("page", "1");
      router.push(`/jobs?${params.toString()}`);
    },
    [router, searchParams]
  );

  const handleSortChange = useCallback(
    (col: SortCol) => {
      const params = new URLSearchParams(searchParams.toString());
      if (sortCol === col) {
        params.set("dir", sortDir === "asc" ? "desc" : "asc");
      } else {
        params.set("sort", col);
        params.set("dir", "desc");
      }
      params.set("page", "1");
      router.push(`/jobs?${params.toString()}`);
    },
    [router, searchParams, sortCol, sortDir]
  );

  const handlePageChange = useCallback(
    (newPage: number) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set("page", String(newPage));
      router.push(`/jobs?${params.toString()}`);
    },
    [router, searchParams]
  );

  // Main jobs list query
  const { data: jobs, isLoading, isError } = useQuery({
    queryKey: [
      "jobs",
      { tab: activeTab, page, search: debouncedSearch, sort: sortCol, dir: sortDir },
    ],
    queryFn: () => {
      if (debouncedSearch) {
        const params = new URLSearchParams();
        params.set("q", debouncedSearch);
        if (activeTab !== "all" && activeTab !== "requests") {
          params.set("status", activeTab);
        }
        return apiGet<Job[]>(`/api/v1/jobs/search?${params.toString()}`);
      }
      const params = new URLSearchParams();
      if (activeTab !== "all" && activeTab !== "requests") {
        params.set("status", activeTab);
      }
      params.set("offset", String((page - 1) * PAGE_SIZE));
      params.set("limit", String(PAGE_SIZE));
      return apiGet<Job[]>(`/api/v1/jobs?${params.toString()}`);
    },
    enabled: activeTab !== "requests",
  });

  // Requests query (only when tab is "requests")
  const { data: requests, isLoading: requestsLoading } = useQuery({
    queryKey: ["job-requests", { page }],
    queryFn: () => apiGet<JobRequestResponse[]>("/api/v1/jobs/requests"),
    enabled: activeTab === "requests",
  });

  // Tab count queries for each job status (useQueries avoids hooks-in-loop violation)
  const countQueryResults = useQueries({
    queries: JOB_STATUSES.map((s) => ({
      queryKey: ["jobs", "count", s],
      queryFn: () => apiGet<Job[]>(`/api/v1/jobs?status=${s}&limit=200`),
      select: (data: Job[]) => data.length,
    })),
  });

  // Pending requests count (filter client-side by status === "pending")
  const requestsCountQuery = useQuery({
    queryKey: ["job-requests", "count"],
    queryFn: () => apiGet<JobRequestResponse[]>("/api/v1/jobs/requests?limit=200"),
    select: (data) => data.filter((r) => r.status === "pending").length,
  });

  // Build count map: status -> count
  const countMap: Record<string, number | undefined> = {};
  JOB_STATUSES.forEach((s, i) => {
    countMap[s] = countQueryResults[i].data;
  });

  // Total count for "All" tab
  const allCount = JOB_STATUSES.reduce((sum, s) => {
    return sum + (countMap[s] ?? 0);
  }, 0);

  // Error handling
  useEffect(() => {
    if (isError) {
      toast.error("Failed to load jobs. Check your connection and try again.", {
        duration: Infinity,
      });
    }
  }, [isError]);

  // Client-side sort
  const sortedJobs = jobs ? sortJobs(jobs, sortCol, sortDir) : [];

  function SortIcon({ col }: { col: SortCol }) {
    if (sortCol !== col) {
      return <ArrowUpDown className="ml-1 inline h-3 w-3 text-gray-400" />;
    }
    return sortDir === "asc" ? (
      <ArrowUp className="ml-1 inline h-3 w-3 text-gray-700" />
    ) : (
      <ArrowDown className="ml-1 inline h-3 w-3 text-gray-700" />
    );
  }

  const getTabCount = (value: string): number | undefined => {
    if (value === "all") return allCount;
    if (value === "requests") return requestsCountQuery.data;
    return countMap[value];
  };

  return (
    <div className="space-y-4">
      {/* Header row: page title + search bar + new job button */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-gray-900">Jobs</h1>
        <div className="flex items-center gap-3">
          <div className="relative w-72">
            <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 pointer-events-none" />
            <Input
              className="pl-8"
              placeholder="Search jobs..."
              value={searchInput}
              onChange={handleSearchChange}
            />
          </div>
          <Button onClick={() => setCreateDialogOpen(true)} data-testid="new-job-button">
            <Plus className="h-4 w-4" data-icon="inline-start" />
            New Job
          </Button>
        </div>
      </div>

      <CreateJobDialog open={createDialogOpen} onOpenChange={setCreateDialogOpen} />

      {/* Status tab bar */}
      <div className="flex items-center border-b border-gray-200">
        {STATUS_TABS.map((tab) => {
          const count = getTabCount(tab.value);
          const isActive = activeTab === tab.value;
          return (
            <button
              key={tab.value}
              onClick={() => handleTabChange(tab.value)}
              className={`py-3 px-4 text-sm transition-colors whitespace-nowrap ${
                isActive
                  ? "border-b-2 border-gray-900 text-gray-900 font-semibold -mb-px"
                  : "text-gray-500 hover:text-gray-700"
              }`}
            >
              {tab.label}
              {count !== undefined && (
                <span className="text-xs text-gray-400 ml-1">({count})</span>
              )}
            </button>
          );
        })}

        {/* Divider before Requests tab */}
        <span className="mx-2 text-gray-300">|</span>

        {/* Requests tab */}
        {(() => {
          const count = requestsCountQuery.data;
          const isActive = activeTab === "requests";
          return (
            <button
              onClick={() => handleTabChange("requests")}
              className={`py-3 px-4 text-sm transition-colors whitespace-nowrap ${
                isActive
                  ? "border-b-2 border-gray-900 text-gray-900 font-semibold -mb-px"
                  : "text-gray-500 hover:text-gray-700"
              }`}
            >
              Requests
              {count !== undefined && (
                <span className="text-xs text-gray-400 ml-1">({count})</span>
              )}
            </button>
          );
        })()}
      </div>

      {/* Data table */}
      <div className="rounded-xl bg-white ring-1 ring-foreground/10 overflow-hidden">
        {activeTab === "requests" ? (
          // Requests table
          <>
            {requestsLoading ? (
              <SkeletonRows />
            ) : !requests || requests.length === 0 ? (
              <EmptyState
                title="No pending requests"
                message="New job requests from clients will appear here..."
              />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      Client Name
                    </TableHead>
                    <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      Description
                    </TableHead>
                    <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      Job Type
                    </TableHead>
                    <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      Preferred Date
                    </TableHead>
                    <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      Status
                    </TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {requests.map((request) => (
                    <TableRow
                      key={request.id}
                      className="cursor-pointer hover:bg-gray-50"
                      onClick={() =>
                        router.push(`/jobs/requests/${request.id}`)
                      }
                    >
                      <TableCell className="py-3 px-4 font-medium text-sm text-gray-900">
                        {request.client_name}
                      </TableCell>
                      <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-xs">
                        {request.description}
                      </TableCell>
                      <TableCell className="py-3 px-4 text-sm text-gray-500">
                        {request.job_type ?? "—"}
                      </TableCell>
                      <TableCell className="py-3 px-4 text-sm text-gray-500">
                        {request.preferred_date
                          ? new Date(request.preferred_date).toLocaleDateString()
                          : "—"}
                      </TableCell>
                      <TableCell className="py-3 px-4">
                        <StatusBadge status={request.status} size="sm" />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </>
        ) : (
          // Jobs table
          <>
            {isLoading ? (
              <SkeletonRows />
            ) : !sortedJobs || sortedJobs.length === 0 ? (
              <EmptyState
                title={
                  activeTab === "all"
                    ? "No jobs found"
                    : `No ${activeTab.replace(/_/g, " ")} jobs`
                }
                message={
                  activeTab === "all"
                    ? "No jobs match your current filters..."
                    : `There are no jobs with ${activeTab.replace(/_/g, " ")} status...`
                }
              />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead
                      className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                      onClick={() => handleSortChange("id")}
                    >
                      Job #
                      <SortIcon col="id" />
                    </TableHead>
                    <TableHead
                      className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                      onClick={() => handleSortChange("description")}
                    >
                      Description
                      <SortIcon col="description" />
                    </TableHead>
                    <TableHead
                      className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                      onClick={() => handleSortChange("status")}
                    >
                      Status
                      <SortIcon col="status" />
                    </TableHead>
                    <TableHead
                      className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                      onClick={() => handleSortChange("created_at")}
                    >
                      Date
                      <SortIcon col="created_at" />
                    </TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sortedJobs.map((job) => (
                    <TableRow
                      key={job.id}
                      className="cursor-pointer hover:bg-gray-50"
                      onClick={() => router.push(`/jobs/${job.id}`)}
                    >
                      <TableCell className="py-3 px-4 font-mono text-sm text-gray-900">
                        {job.id.slice(0, 8).toUpperCase()}
                      </TableCell>
                      <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-xs">
                        {job.description}
                      </TableCell>
                      <TableCell className="py-3 px-4">
                        <StatusBadge status={job.status} size="sm" />
                      </TableCell>
                      <TableCell className="py-3 px-4 text-sm text-gray-500">
                        {new Date(job.created_at).toLocaleDateString()}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </>
        )}
      </div>

      {/* Pagination (only for jobs, not requests) */}
      {activeTab !== "requests" && (
        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-500">Showing page {page}</span>
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => handlePageChange(page - 1)}
              disabled={page === 1}
            >
              Previous
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => handlePageChange(page + 1)}
              disabled={!jobs || jobs.length < PAGE_SIZE}
            >
              Next
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}

function SkeletonRows() {
  return (
    <div className="divide-y">
      {[...Array(5)].map((_, i) => (
        <div key={i} className="flex items-center gap-4 px-4 h-12">
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-4 w-16" />
          <Skeleton className="h-4 w-24" />
        </div>
      ))}
    </div>
  );
}

function EmptyState({ title, message }: { title: string; message: string }) {
  return (
    <div className="px-4 py-12 text-center">
      <p className="text-sm font-medium text-gray-900">{title}</p>
      <p className="mt-1 text-sm text-gray-500">{message}</p>
    </div>
  );
}
