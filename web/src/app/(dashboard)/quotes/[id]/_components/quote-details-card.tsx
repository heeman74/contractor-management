import Link from "next/link";
import type { Quote, Job } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { DetailField } from "@/components/shared/detail-field";
import { formatDate } from "@/lib/format";

interface QuoteDetailsCardProps {
  quote: Quote;
  job: Job | undefined;
}

export function QuoteDetailsCard({ quote, job }: QuoteDetailsCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Quote Details</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
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

        <DetailField label="Job">
          <Link
            href={`/jobs/${quote.job_id}`}
            className="text-sm text-foreground hover:underline truncate block max-w-full"
          >
            {job?.description ?? quote.job_id.slice(0, 8)}
          </Link>
        </DetailField>

        <DetailField label="Expiry Date">
          <p className="text-sm text-gray-900">
            {formatDate(quote.expiry_date, "No expiry")}
          </p>
        </DetailField>

        {quote.viewed_at && (
          <p className="text-xs text-green-600">
            Viewed by client on {formatDate(quote.viewed_at)}
          </p>
        )}

        <DetailField label="Revision">
          <p className="text-sm text-gray-900">v{quote.revision_number}</p>
        </DetailField>

        <DetailField label="Created">
          <p className="text-sm text-gray-900">{formatDate(quote.created_at)}</p>
        </DetailField>
      </CardContent>
    </Card>
  );
}
