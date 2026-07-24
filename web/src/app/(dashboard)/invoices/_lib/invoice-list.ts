import type { Invoice, Job } from "@/types/api";
import { ALL_TAB, type SortDirection } from "@/hooks/use-list-table-filters";
import { isInvoiceOverdue } from "./invoice-status";

export { ALL_TAB };
export type { SortDirection };

export const OVERDUE_TAB = "overdue";
export const DRAFT_TAB = "draft";

export const DEFAULT_SORT_COLUMN: SortColumn = "due_date";

export type SortColumn =
  | "invoice_number"
  | "total"
  | "amount_paid"
  | "due_date"
  | "status";

export interface StatusTab {
  label: string;
  value: string;
}

export const INVOICE_STATUS_TABS: StatusTab[] = [
  { label: "All", value: ALL_TAB },
  { label: "Unpaid", value: "unpaid" },
  { label: "Partially Paid", value: "partially_paid" },
  { label: "Paid", value: "paid" },
  { label: "Overdue", value: OVERDUE_TAB },
  { label: "Draft", value: DRAFT_TAB },
];

export type JobsById = Map<string, Job>;

export function buildJobsById(jobs: Job[] | undefined): JobsById {
  return new Map((jobs ?? []).map((job) => [job.id, job]));
}

function isDraft(invoice: Invoice): boolean {
  return invoice.finalized_at === null;
}

export function filterInvoicesByTab(invoices: Invoice[], tab: string): Invoice[] {
  if (tab === ALL_TAB) return invoices;
  if (tab === OVERDUE_TAB) return invoices.filter(isInvoiceOverdue);
  if (tab === DRAFT_TAB) return invoices.filter(isDraft);
  return invoices.filter((invoice) => invoice.status === tab);
}

export function countInvoicesByTab(invoices: Invoice[], tab: string): number {
  return filterInvoicesByTab(invoices, tab).length;
}

export function matchesInvoiceSearch(
  invoice: Invoice,
  query: string,
  jobsById: JobsById
): boolean {
  const normalized = query.toLowerCase();
  const job = jobsById.get(invoice.job_id);
  return (
    invoice.invoice_number.toLowerCase().includes(normalized) ||
    (job?.description?.toLowerCase().includes(normalized) ?? false) ||
    (job?.client_name?.toLowerCase().includes(normalized) ?? false)
  );
}

function sortableValue(invoice: Invoice, column: SortColumn): string | number {
  switch (column) {
    case "invoice_number":
      return invoice.invoice_number.toLowerCase();
    case "total":
      return Number(invoice.total);
    case "amount_paid":
      return Number(invoice.amount_paid);
    case "due_date":
      return invoice.due_date ?? "";
    case "status":
      return invoice.status;
  }
}

export function sortInvoices(
  invoices: Invoice[],
  column: SortColumn,
  direction: SortDirection
): Invoice[] {
  const orderFactor = direction === "asc" ? 1 : -1;
  return [...invoices].sort((a, b) => {
    const valueA = sortableValue(a, column);
    const valueB = sortableValue(b, column);
    if (valueA < valueB) return -orderFactor;
    if (valueA > valueB) return orderFactor;
    return 0;
  });
}
