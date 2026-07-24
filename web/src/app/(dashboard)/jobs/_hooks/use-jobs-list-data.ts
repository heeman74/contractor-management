import { useEffect } from "react";
import { useQueries, useQuery } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet } from "@/lib/api-client";
import type { Job, JobRequestResponse } from "@/types/api";
import {
  ALL_TAB,
  buildJobsListEndpoint,
  buildJobsSearchEndpoint,
  COUNT_FETCH_LIMIT,
  JOB_STATUSES,
  PAGE_SIZE,
  PENDING_REQUEST_STATUS,
  REQUESTS_TAB,
  sortJobs,
  type SortColumn,
  type SortDirection,
} from "../_lib/job-list";

interface UseJobsListDataArgs {
  activeTab: string;
  page: number;
  search: string;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
}

export interface JobsListData {
  jobs: Job[];
  isJobsLoading: boolean;
  hasMorePages: boolean;
  requests: JobRequestResponse[] | undefined;
  isRequestsLoading: boolean;
  getTabCount: (tabValue: string) => number | undefined;
}

const LOAD_ERROR_MESSAGE =
  "Failed to load jobs. Check your connection and try again.";

export function useJobsListData({
  activeTab,
  page,
  search,
  sortColumn,
  sortDirection,
}: UseJobsListDataArgs): JobsListData {
  const {
    data: jobs,
    isLoading: isJobsLoading,
    isError,
  } = useQuery({
    queryKey: [
      "jobs",
      { tab: activeTab, page, search, sort: sortColumn, dir: sortDirection },
    ],
    queryFn: () =>
      apiGet<Job[]>(
        search
          ? buildJobsSearchEndpoint(activeTab, search)
          : buildJobsListEndpoint(activeTab, page)
      ),
    enabled: activeTab !== REQUESTS_TAB,
  });

  const { data: requests, isLoading: isRequestsLoading } = useQuery({
    queryKey: ["job-requests", { page }],
    queryFn: () => apiGet<JobRequestResponse[]>("/api/v1/jobs/requests"),
    enabled: activeTab === REQUESTS_TAB,
  });

  const statusCountQueries = useQueries({
    queries: JOB_STATUSES.map((status) => ({
      queryKey: ["jobs", "count", status],
      queryFn: () =>
        apiGet<Job[]>(`/api/v1/jobs?status=${status}&limit=${COUNT_FETCH_LIMIT}`),
      select: (data: Job[]) => data.length,
    })),
  });

  const pendingRequestsCountQuery = useQuery({
    queryKey: ["job-requests", "count"],
    queryFn: () =>
      apiGet<JobRequestResponse[]>(
        `/api/v1/jobs/requests?limit=${COUNT_FETCH_LIMIT}`
      ),
    select: (data) =>
      data.filter((request) => request.status === PENDING_REQUEST_STATUS).length,
  });

  useEffect(() => {
    if (isError) toast.error(LOAD_ERROR_MESSAGE, { duration: Infinity });
  }, [isError]);

  const statusCounts = new Map<string, number | undefined>(
    JOB_STATUSES.map((status, index) => [status, statusCountQueries[index].data])
  );

  const allCount = JOB_STATUSES.reduce(
    (sum, status) => sum + (statusCounts.get(status) ?? 0),
    0
  );

  const getTabCount = (tabValue: string): number | undefined => {
    if (tabValue === ALL_TAB) return allCount;
    if (tabValue === REQUESTS_TAB) return pendingRequestsCountQuery.data;
    return statusCounts.get(tabValue);
  };

  const sortedJobs = jobs ? sortJobs(jobs, sortColumn, sortDirection) : [];

  return {
    jobs: sortedJobs,
    isJobsLoading,
    hasMorePages: !!jobs && jobs.length >= PAGE_SIZE,
    requests,
    isRequestsLoading,
    getTabCount,
  };
}
