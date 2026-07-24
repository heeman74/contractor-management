import { useRouter } from "next/navigation";
import { cn } from "@/lib/utils";
import { formatCurrency, formatDate } from "@/lib/format";
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
import type { Invoice } from "@/types/api";
import { invoiceBalance, isInvoiceOverdue } from "../_lib/invoice-status";
import type { JobsById, SortColumn, SortDirection } from "../_lib/invoice-list";

const EMPTY_VALUE = "—";
const NUMERIC_HEADER_CLASSES = "text-right";

interface InvoicesTableProps {
  invoices: Invoice[];
  jobsById: JobsById;
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  onSortChange: (column: SortColumn) => void;
}

function InvoiceRow({
  invoice,
  jobsById,
}: {
  invoice: Invoice;
  jobsById: JobsById;
}) {
  const router = useRouter();
  const overdue = isInvoiceOverdue(invoice);
  const job = jobsById.get(invoice.job_id);
  return (
    <TableRow
      className={cn(
        "cursor-pointer hover:bg-gray-50",
        overdue && "border-l-2 border-red-400"
      )}
      onClick={() => router.push(`/invoices/${invoice.id}`)}
    >
      <TableCell className="py-3 px-4 font-mono text-sm text-gray-900">
        {invoice.invoice_number}
      </TableCell>
      <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-[140px]">
        {job?.description ?? EMPTY_VALUE}
      </TableCell>
      <TableCell className="py-3 px-4 text-sm text-gray-700">
        {job?.client_name ?? EMPTY_VALUE}
      </TableCell>
      <TableCell className="py-3 px-4 font-mono text-sm text-gray-900 text-right">
        {formatCurrency(invoice.total)}
      </TableCell>
      <TableCell className="py-3 px-4 font-mono text-sm text-green-700 text-right">
        {formatCurrency(invoice.amount_paid)}
      </TableCell>
      <TableCell
        className={cn(
          "py-3 px-4 font-mono text-sm text-right",
          overdue ? "text-red-700" : "text-gray-900"
        )}
      >
        {formatCurrency(invoiceBalance(invoice))}
      </TableCell>
      <TableCell className="py-3 px-4">
        <StatusBadge status={overdue ? "overdue" : invoice.status} size="sm" />
      </TableCell>
      <TableCell
        className={cn(
          "py-3 px-4 text-sm",
          overdue ? "text-red-600 font-medium" : "text-gray-500"
        )}
      >
        {formatDate(invoice.due_date)}
      </TableCell>
    </TableRow>
  );
}

export function InvoicesTable({
  invoices,
  jobsById,
  sortColumn,
  sortDirection,
  onSortChange,
}: InvoicesTableProps) {
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
          {sortableHeader("invoice_number", "Invoice #")}
          <PlainTableHeader label="Job" />
          <PlainTableHeader label="Client" />
          {sortableHeader("total", "Total", NUMERIC_HEADER_CLASSES)}
          {sortableHeader("amount_paid", "Paid", NUMERIC_HEADER_CLASSES)}
          <PlainTableHeader label="Balance" className={NUMERIC_HEADER_CLASSES} />
          {sortableHeader("status", "Status")}
          {sortableHeader("due_date", "Due Date")}
        </TableRow>
      </TableHeader>
      <TableBody>
        {invoices.map((invoice) => (
          <InvoiceRow
            key={invoice.id}
            invoice={invoice}
            jobsById={jobsById}
          />
        ))}
      </TableBody>
    </Table>
  );
}
