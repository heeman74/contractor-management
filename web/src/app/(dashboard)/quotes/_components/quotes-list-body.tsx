import { ListEmptyState } from "@/components/shared/list-empty-state";
import { TableSkeleton } from "@/components/shared/table-skeleton";
import type { Quote } from "@/types/api";
import {
  ALL_TAB,
  type JobsById,
  type SortColumn,
  type SortDirection,
} from "../_lib/quote-list";
import { QuotesTable } from "./quotes-table";

const SKELETON_WIDTHS = ["w-24", "w-32", "w-20", "w-16", "w-16"];

interface QuotesListBodyProps {
  quotes: Quote[];
  isLoading: boolean;
  jobsById: JobsById;
  activeTab: string;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  onSortChange: (column: SortColumn) => void;
}

function emptyStateText(activeTab: string) {
  if (activeTab === ALL_TAB) {
    return {
      title: "No quotes yet",
      message:
        "Quotes are created from job detail pages. Open a job in Quote status to get started.",
    };
  }
  return {
    title: `No ${activeTab} quotes`,
    message: `There are no quotes with ${activeTab} status.`,
  };
}

export function QuotesListBody({
  quotes,
  isLoading,
  jobsById,
  activeTab,
  sortColumn,
  sortDirection,
  onSortChange,
}: QuotesListBodyProps) {
  return (
    <div className="rounded-xl bg-white ring-1 ring-foreground/10 overflow-hidden">
      {isLoading ? (
        <TableSkeleton columnWidths={SKELETON_WIDTHS} />
      ) : quotes.length === 0 ? (
        <ListEmptyState {...emptyStateText(activeTab)} />
      ) : (
        <QuotesTable
          quotes={quotes}
          jobsById={jobsById}
          sortColumn={sortColumn}
          sortDirection={sortDirection}
          onSortChange={onSortChange}
        />
      )}
    </div>
  );
}
