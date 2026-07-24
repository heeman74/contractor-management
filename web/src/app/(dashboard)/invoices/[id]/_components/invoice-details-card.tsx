import Link from "next/link";
import type { Invoice, Job } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { DetailField } from "@/components/shared/detail-field";
import { cn } from "@/lib/utils";
import { formatDate } from "@/lib/format";

interface InvoiceDetailsCardProps {
  invoice: Invoice;
  job: Job | undefined;
  isOverdue: boolean;
}

export function InvoiceDetailsCard({
  invoice,
  job,
  isOverdue,
}: InvoiceDetailsCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Invoice Details</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <DetailField label="Due Date">
          <p
            className={cn(
              "text-sm",
              isOverdue ? "text-red-600 font-medium" : "text-gray-900"
            )}
          >
            {formatDate(invoice.due_date)}
          </p>
        </DetailField>

        <DetailField label="Issued">
          <p className="text-sm text-gray-900">{formatDate(invoice.issued_at)}</p>
        </DetailField>

        {invoice.finalized_at && (
          <DetailField label="Finalized">
            <p className="text-sm text-gray-900">
              {formatDate(invoice.finalized_at)}
            </p>
          </DetailField>
        )}

        <DetailField label="Job">
          <Link
            href={`/jobs/${invoice.job_id}`}
            className="text-sm text-foreground hover:underline"
          >
            {job?.description ?? invoice.job_id.slice(0, 8)}
          </Link>
        </DetailField>

        <DetailField label="Client">
          {job?.client_id ? (
            <Link
              href={`/clients/${job.client_id}`}
              className="text-sm text-foreground hover:text-foreground hover:underline"
            >
              {job.client_name ?? job.client_id.slice(0, 8)}
            </Link>
          ) : (
            <p className="text-sm text-gray-900">{job?.client_name ?? "—"}</p>
          )}
        </DetailField>

        {invoice.quote_id && (
          <DetailField label="Quote">
            <Link
              href={`/quotes/${invoice.quote_id}`}
              className="text-sm text-foreground hover:underline"
            >
              View Quote
            </Link>
          </DetailField>
        )}
      </CardContent>
    </Card>
  );
}
