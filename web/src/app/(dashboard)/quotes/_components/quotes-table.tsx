import { useRouter } from "next/navigation";
import { formatDate } from "@/lib/format";
import {
  PlainTableHeader,
  SortableTableHeader,
} from "@/components/shared/sortable-table-header";
import { StatusBadge } from "@/components/shared/status-badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { Quote } from "@/types/api";
import {
  formatQuoteReference,
  formatQuoteTotal,
  type JobsById,
  type SortColumn,
  type SortDirection,
} from "../_lib/quote-list";

const EMPTY_VALUE = "—";

interface QuotesTableProps {
  quotes: Quote[];
  jobsById: JobsById;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  onSortChange: (column: SortColumn) => void;
}

export function QuotesTable({
  quotes,
  jobsById,
  sortColumn,
  sortDirection,
  onSortChange,
}: QuotesTableProps) {
  const router = useRouter();
  const sortableHeader = (
    column: SortColumn,
    label: string,
    className?: string
  ) => (
    <SortableTableHeader
      column={column}
      label={label}
      activeColumn={sortColumn}
      direction={sortDirection}
      onSort={onSortChange}
      className={className}
    />
  );

  return (
    <Table>
      <TableHeader>
        <TableRow>
          {sortableHeader("id", "Quote #")}
          <PlainTableHeader label="Job" />
          <PlainTableHeader label="Client" />
          {sortableHeader("total", "Total", "text-right")}
          {sortableHeader("status", "Status")}
          {sortableHeader("created_at", "Date")}
        </TableRow>
      </TableHeader>
      <TableBody>
        {quotes.map((quote) => {
          const job = jobsById.get(quote.job_id);
          return (
            <TableRow
              key={quote.id}
              className="cursor-pointer hover:bg-gray-50"
              onClick={() => router.push(`/quotes/${quote.id}`)}
            >
              <TableCell className="py-3 px-4 font-mono text-sm text-gray-900">
                {formatQuoteReference(quote.id)}
              </TableCell>
              <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-[160px]">
                {job?.description ?? EMPTY_VALUE}
              </TableCell>
              <TableCell className="py-3 px-4 text-sm text-gray-700">
                {job?.client_name ?? EMPTY_VALUE}
              </TableCell>
              <TableCell className="py-3 px-4 font-mono text-sm text-gray-900 text-right">
                {formatQuoteTotal(quote.total)}
              </TableCell>
              <TableCell className="py-3 px-4">
                <StatusBadge status={quote.status} size="sm" />
              </TableCell>
              <TableCell className="py-3 px-4 text-sm text-gray-500">
                {formatDate(quote.created_at)}
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}
