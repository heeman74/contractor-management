import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet } from "@/lib/api-client";
import type { Invoice, Job } from "@/types/api";
import { DEFAULT_PAGE_SIZE } from "@/hooks/use-list-table-filters";
import {
  buildJobsById,
  countInvoicesByTab,
  filterInvoicesByTab,
  type JobsById,
  matchesInvoiceSearch,
  sortInvoices,
  type SortColumn,
  type SortDirection,
} from "../_lib/invoice-list";

interface UseInvoicesListDataArgs {
  activeTab: string;
  page: number;
  search: string;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
}

export interface InvoicesListData {
  isLoading: boolean;
  isLoaded: boolean;
  jobsById: JobsById;
  visibleInvoices: Invoice[];
  totalCount: number;
  getTabCount: (tabValue: string) => number;
}

const LOAD_ERROR_MESSAGE =
  "Failed to load invoices. Check your connection and try again.";

export function useInvoicesListData({
  activeTab,
  page,
  search,
  sortColumn,
  sortDirection,
}: UseInvoicesListDataArgs): InvoicesListData {
  const {
    data: invoices,
    isLoading,
    isError,
  } = useQuery({
    queryKey: ["invoices"],
    queryFn: () => apiGet<Invoice[]>("/api/v1/invoices/"),
  });

  const { data: jobs } = useQuery({
    queryKey: ["jobs"],
    queryFn: () => apiGet<Job[]>("/api/v1/jobs"),
  });

  useEffect(() => {
    if (isError) toast.error(LOAD_ERROR_MESSAGE, { duration: Infinity });
  }, [isError]);

  const allInvoices = invoices ?? [];
  const jobsById = buildJobsById(jobs);

  const filtered = filterInvoicesByTab(allInvoices, activeTab);
  const searched = search
    ? filtered.filter((invoice) =>
        matchesInvoiceSearch(invoice, search, jobsById)
      )
    : filtered;
  const sorted = sortInvoices(searched, sortColumn, sortDirection);

  const startIndex = (page - 1) * DEFAULT_PAGE_SIZE;
  const visibleInvoices = sorted.slice(startIndex, startIndex + DEFAULT_PAGE_SIZE);

  return {
    isLoading,
    isLoaded: invoices !== undefined,
    jobsById,
    visibleInvoices,
    totalCount: sorted.length,
    getTabCount: (tabValue) => countInvoicesByTab(allInvoices, tabValue),
  };
}
