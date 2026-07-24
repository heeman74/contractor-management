import type { Job, JobStatus } from "@/types/api";
import {
  ALL_TAB,
  DEFAULT_PAGE_SIZE,
  type SortDirection,
} from "@/hooks/use-list-table-filters";

export { ALL_TAB };
export type { SortDirection };

export const PAGE_SIZE = DEFAULT_PAGE_SIZE;
export const COUNT_FETCH_LIMIT = 200;

export const REQUESTS_TAB = "requests";
export const PENDING_REQUEST_STATUS = "pending";

export const DEFAULT_SORT_COLUMN: SortColumn = "created_at";

export type SortColumn = "id" | "description" | "status" | "created_at";

export interface StatusTab {
  label: string;
  value: string;
}

export const STATUS_TABS: StatusTab[] = [
  { label: "All", value: ALL_TAB },
  { label: "Quote", value: "quote" },
  { label: "Scheduled", value: "scheduled" },
  { label: "In Progress", value: "in_progress" },
  { label: "Complete", value: "complete" },
  { label: "Invoiced", value: "invoiced" },
];

export const JOB_STATUSES: JobStatus[] = [
  "quote",
  "scheduled",
  "in_progress",
  "complete",
  "invoiced",
];

function sortableValue(job: Job, column: SortColumn): string | number {
  switch (column) {
    case "id":
      return job.id;
    case "description":
      return job.description.toLowerCase();
    case "status":
      return job.status;
    case "created_at":
      return job.created_at;
  }
}

export function sortJobs(
  jobs: Job[],
  column: SortColumn,
  direction: SortDirection
): Job[] {
  const orderFactor = direction === "asc" ? 1 : -1;
  return [...jobs].sort((a, b) => {
    const valueA = sortableValue(a, column);
    const valueB = sortableValue(b, column);
    if (valueA < valueB) return -orderFactor;
    if (valueA > valueB) return orderFactor;
    return 0;
  });
}

function isJobStatusTab(tab: string): boolean {
  return tab !== ALL_TAB && tab !== REQUESTS_TAB;
}

export function buildJobsListEndpoint(tab: string, page: number): string {
  const params = new URLSearchParams();
  if (isJobStatusTab(tab)) params.set("status", tab);
  params.set("offset", String((page - 1) * PAGE_SIZE));
  params.set("limit", String(PAGE_SIZE));
  return `/api/v1/jobs?${params.toString()}`;
}

export function buildJobsSearchEndpoint(tab: string, search: string): string {
  const params = new URLSearchParams();
  params.set("q", search);
  if (isJobStatusTab(tab)) params.set("status", tab);
  return `/api/v1/jobs/search?${params.toString()}`;
}
