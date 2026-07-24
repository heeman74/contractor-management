import { ListEmptyState } from "@/components/shared/list-empty-state";
import { TableSkeleton } from "@/components/shared/table-skeleton";
import type { Invoice } from "@/types/api";
import { ALL_TAB, type JobsById, type SortColumn, type SortDirection } from "../_lib/invoice-list";
import { InvoicesTable } from "./invoices-table";

const SKELETON_WIDTHS = [
  "w-24",
  "w-32",
  "w-24",
  "w-16",
  "w-16",
  "w-16",
  "w-20",
  "w-20",
];

interface InvoicesListBodyProps {
  invoices: Invoice[];
  isLoading: boolean;
  jobsById: JobsById;
  activeTab: string;
  hasSearch: boolean;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  onSortChange: (column: SortColumn) => void;
}

function humanizeStatus(tab: string): string {
  return tab.replace(/_/g, " ");
}

function emptyStateText(activeTab: string, hasSearch: boolean) {
  const isDefaultView = activeTab === ALL_TAB && !hasSearch;
  if (isDefaultView) {
    return {
      title: "No invoices yet",
      message:
        "Invoices are generated from approved quotes. Approve a quote to create an invoice.",
    };
  }
  return {
    title: `No ${humanizeStatus(activeTab)} invoices`,
    message: "No invoices match the current filter.",
  };
}

export function InvoicesListBody({
  invoices,
  isLoading,
  jobsById,
  activeTab,
  hasSearch,
  sortColumn,
  sortDirection,
  onSortChange,
}: InvoicesListBodyProps) {
  return (
    <div className="rounded-xl bg-white ring-1 ring-foreground/10 overflow-hidden">
      {isLoading ? (
        <TableSkeleton columnWidths={SKELETON_WIDTHS} />
      ) : invoices.length === 0 ? (
        <ListEmptyState {...emptyStateText(activeTab, hasSearch)} />
      ) : (
        <InvoicesTable
          invoices={invoices}
          jobsById={jobsById}
          sortColumn={sortColumn}
          sortDirection={sortDirection}
          onSortChange={onSortChange}
        />
      )}
    </div>
  );
}
