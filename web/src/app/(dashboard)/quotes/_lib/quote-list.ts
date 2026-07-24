import type { Job, Quote, QuoteStatus } from "@/types/api";
import { ALL_TAB, type SortDirection } from "@/hooks/use-list-table-filters";

export { ALL_TAB };
export type { SortDirection };

export const HIDDEN_STATUS: QuoteStatus = "revised";
export const DEFAULT_SORT_COLUMN: SortColumn = "created_at";
const QUOTE_REFERENCE_LENGTH = 6;

export type SortColumn = "id" | "total" | "status" | "created_at";

export interface StatusTab {
  label: string;
  value: string;
}

export const QUOTE_STATUS_TABS: StatusTab[] = [
  { label: "All", value: ALL_TAB },
  { label: "Draft", value: "draft" },
  { label: "Sent", value: "sent" },
  { label: "Viewed", value: "viewed" },
  { label: "Approved", value: "approved" },
  { label: "Declined", value: "declined" },
  { label: "Expired", value: "expired" },
];

export const QUOTE_STATUSES: QuoteStatus[] = [
  "draft",
  "sent",
  "viewed",
  "approved",
  "declined",
  "expired",
];

export type JobsById = Map<string, Job>;

export function buildJobsById(jobs: Job[] | undefined): JobsById {
  return new Map((jobs ?? []).map((job) => [job.id, job]));
}

export function formatQuoteReference(quoteId: string): string {
  return `QT-${quoteId.slice(0, QUOTE_REFERENCE_LENGTH).toUpperCase()}`;
}

export function formatQuoteTotal(total: number | string): string {
  return `$${Number(total).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

export function filterQuotesByTab(quotes: Quote[], tab: string): Quote[] {
  if (tab === ALL_TAB) {
    return quotes.filter((quote) => quote.status !== HIDDEN_STATUS);
  }
  return quotes.filter((quote) => quote.status === tab);
}

export function countQuotesByTab(quotes: Quote[], tab: string): number {
  return filterQuotesByTab(quotes, tab).length;
}

export function matchesQuoteSearch(
  quote: Quote,
  query: string,
  jobsById: JobsById
): boolean {
  const normalized = query.toLowerCase();
  const job = jobsById.get(quote.job_id);
  return (
    formatQuoteReference(quote.id).toLowerCase().includes(normalized) ||
    (job?.description?.toLowerCase().includes(normalized) ?? false) ||
    (job?.client_name?.toLowerCase().includes(normalized) ?? false)
  );
}

function sortableValue(quote: Quote, column: SortColumn): string | number {
  switch (column) {
    case "id":
      return quote.id;
    case "total":
      return Number(quote.total);
    case "status":
      return quote.status;
    case "created_at":
      return quote.created_at;
  }
}

export function sortQuotes(
  quotes: Quote[],
  column: SortColumn,
  direction: SortDirection
): Quote[] {
  const orderFactor = direction === "asc" ? 1 : -1;
  return [...quotes].sort((a, b) => {
    const valueA = sortableValue(a, column);
    const valueB = sortableValue(b, column);
    if (valueA < valueB) return -orderFactor;
    if (valueA > valueB) return orderFactor;
    return 0;
  });
}
