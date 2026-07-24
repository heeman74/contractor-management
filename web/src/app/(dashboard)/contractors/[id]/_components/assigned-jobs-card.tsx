import { useRouter } from "next/navigation";
import { StatusBadge } from "@/components/shared/status-badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { Job } from "@/types/api";

const COLUMN_HEADER_CLASS =
  "text-xs font-semibold text-gray-500 uppercase tracking-wide";

export function AssignedJobsCard({ jobs }: { jobs: Job[] | undefined }) {
  const router = useRouter();

  return (
    <Card>
      <CardHeader className="pb-4">
        <CardTitle className="text-base font-semibold text-gray-900">
          Assigned Jobs
        </CardTitle>
      </CardHeader>
      <CardContent className="p-0">
        {!jobs || jobs.length === 0 ? (
          <div className="px-6 py-8 text-center">
            <p className="text-sm text-gray-500">
              No jobs currently assigned to this contractor.
            </p>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className={COLUMN_HEADER_CLASS}>Job #</TableHead>
                <TableHead className={COLUMN_HEADER_CLASS}>Title</TableHead>
                <TableHead className={COLUMN_HEADER_CLASS}>Status</TableHead>
                <TableHead className={COLUMN_HEADER_CLASS}>Client</TableHead>
                <TableHead className={COLUMN_HEADER_CLASS}>Date</TableHead>
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
                    {job.client_name ?? "—"}
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-500">
                    {new Date(job.created_at).toLocaleDateString()}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
