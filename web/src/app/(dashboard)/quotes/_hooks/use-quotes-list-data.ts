import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet } from "@/lib/api-client";
import type { Job, Quote } from "@/types/api";
import { DEFAULT_PAGE_SIZE } from "@/hooks/use-list-table-filters";
import {
  buildJobsById,
  countQuotesByTab,
  filterQuotesByTab,
  type JobsById,
  matchesQuoteSearch,
  sortQuotes,
  type SortColumn,
  type SortDirection,
} from "../_lib/quote-list";

interface UseQuotesListDataArgs {
  activeTab: string;
  page: number;
  search: string;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
}

export interface QuotesListData {
  isLoading: boolean;
  isLoaded: boolean;
  jobsById: JobsById;
  visibleQuotes: Quote[];
  totalCount: number;
  getTabCount: (tabValue: string) => number | undefined;
}

const LOAD_ERROR_MESSAGE =
  "Failed to load quotes. Check your connection and try again.";

export function useQuotesListData({
  activeTab,
  page,
  search,
  sortColumn,
  sortDirection,
}: UseQuotesListDataArgs): QuotesListData {
  const {
    data: quotes,
    isLoading,
    isError,
  } = useQuery({
    queryKey: ["quotes"],
    queryFn: () => apiGet<Quote[]>("/api/v1/quotes/"),
  });

  const { data: jobs } = useQuery({
    queryKey: ["jobs-all"],
    queryFn: () => apiGet<Job[]>("/api/v1/jobs/"),
  });

  useEffect(() => {
    if (isError) toast.error(LOAD_ERROR_MESSAGE, { duration: Infinity });
  }, [isError]);

  const allQuotes = quotes ?? [];
  const jobsById = buildJobsById(jobs);

  const filtered = filterQuotesByTab(allQuotes, activeTab);
  const searched = search
    ? filtered.filter((quote) => matchesQuoteSearch(quote, search, jobsById))
    : filtered;
  const sorted = sortQuotes(searched, sortColumn, sortDirection);

  const startIndex = (page - 1) * DEFAULT_PAGE_SIZE;
  const visibleQuotes = sorted.slice(startIndex, startIndex + DEFAULT_PAGE_SIZE);

  return {
    isLoading,
    isLoaded: quotes !== undefined,
    jobsById,
    visibleQuotes,
    totalCount: sorted.length,
    getTabCount: (tabValue) =>
      quotes ? countQuotesByTab(allQuotes, tabValue) : undefined,
  };
}
