import { useRouter } from "next/navigation";
import { PlainTableHeader } from "@/components/shared/sortable-table-header";
import { StatusBadge } from "@/components/shared/status-badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatDate } from "@/lib/format";
import type { JobRequestResponse } from "@/types/api";

const COLUMN_HEADERS = [
  "Client Name",
  "Description",
  "Job Type",
  "Preferred Date",
  "Status",
];

const EMPTY_VALUE = "—";

export function JobRequestsTable({
  requests,
}: {
  requests: JobRequestResponse[];
}) {
  const router = useRouter();
  return (
    <Table>
      <TableHeader>
        <TableRow>
          {COLUMN_HEADERS.map((header) => (
            <PlainTableHeader key={header} label={header} />
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>
        {requests.map((request) => (
          <TableRow
            key={request.id}
            className="cursor-pointer hover:bg-gray-50"
            onClick={() => router.push(`/jobs/requests/${request.id}`)}
          >
            <TableCell className="py-3 px-4 font-medium text-sm text-gray-900">
              {request.client_name}
            </TableCell>
            <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-xs">
              {request.description}
            </TableCell>
            <TableCell className="py-3 px-4 text-sm text-gray-500">
              {request.job_type ?? EMPTY_VALUE}
            </TableCell>
            <TableCell className="py-3 px-4 text-sm text-gray-500">
              {formatDate(request.preferred_date)}
            </TableCell>
            <TableCell className="py-3 px-4">
              <StatusBadge status={request.status} size="sm" />
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
