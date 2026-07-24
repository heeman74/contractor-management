import { useRouter } from "next/navigation";
import { SortableTableHeader } from "@/components/shared/sortable-table-header";
import { StatusBadge } from "@/components/shared/status-badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { Job } from "@/types/api";
import type { SortColumn, SortDirection } from "../_lib/job-list";

const SORTABLE_COLUMNS: { column: SortColumn; label: string }[] = [
  { column: "id", label: "Job #" },
  { column: "description", label: "Description" },
  { column: "status", label: "Status" },
  { column: "created_at", label: "Date" },
];

interface JobsTableProps {
  jobs: Job[];
  sortColumn: SortColumn;
  sortDirection: SortDirection;
  onSortChange: (column: SortColumn) => void;
}

export function JobsTable({
  jobs,
  sortColumn,
  sortDirection,
  onSortChange,
}: JobsTableProps) {
  const router = useRouter();
  return (
    <Table>
      <TableHeader>
        <TableRow>
          {SORTABLE_COLUMNS.map(({ column, label }) => (
            <SortableTableHeader
              key={column}
              column={column}
              label={label}
              activeColumn={sortColumn}
              direction={sortDirection}
              onSort={onSortChange}
            />
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>
        {jobs.map((job) => (
          <TableRow
            key={job.id}
            className="cursor-pointer hover:bg-gray-50"
            onClick={() => router.push(`/jobs/${job.id}`)}
          >
            <TableCell className="py-3 px-4 font-mono text-sm text-gray-900">
              {job.id.slice(0, 8).toUpperCase()}
            </TableCell>
            <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-xs">
              {job.description}
            </TableCell>
            <TableCell className="py-3 px-4">
              <StatusBadge status={job.status} size="sm" />
            </TableCell>
            <TableCell className="py-3 px-4 text-sm text-gray-500">
              {new Date(job.created_at).toLocaleDateString()}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
