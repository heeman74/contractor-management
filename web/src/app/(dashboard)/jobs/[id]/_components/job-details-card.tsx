import Link from "next/link";
import type { Job } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

function FieldLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
      {children}
    </p>
  );
}

function DetailField({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <FieldLabel>{label}</FieldLabel>
      {children}
    </div>
  );
}

function LinkedEntityField({
  label,
  href,
  name,
}: {
  label: string;
  href: string | null;
  name: string | null;
}) {
  return (
    <DetailField label={label}>
      {href ? (
        <Link
          href={href}
          className="text-sm text-foreground hover:text-foreground hover:underline"
        >
          {name}
        </Link>
      ) : (
        <p className="text-sm font-normal text-gray-900">Not assigned</p>
      )}
    </DetailField>
  );
}

export function JobDetailsCard({ job }: { job: Job }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Job Details</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <LinkedEntityField
          label="Contractor"
          href={job.contractor_id ? `/contractors/${job.contractor_id}` : null}
          name={job.contractor_name ?? job.contractor_id?.slice(0, 8) ?? null}
        />
        <LinkedEntityField
          label="Client"
          href={job.client_id ? `/clients/${job.client_id}` : null}
          name={job.client_name ?? job.client_id?.slice(0, 8) ?? null}
        />
        <LinkedEntityField
          label="Project"
          href={job.project_id ? "/projects" : null}
          name={job.project_name ?? job.project_id?.slice(0, 8) ?? null}
        />
        <LinkedEntityField
          label="Manager"
          href={job.manager_id ? "/team" : null}
          name={job.manager_name ?? job.manager_id?.slice(0, 8) ?? null}
        />

        <DetailField label="Scheduled Date">
          <p className="text-sm font-normal text-gray-900">
            {job.scheduled_completion_date
              ? new Date(job.scheduled_completion_date).toLocaleDateString()
              : "Not scheduled"}
          </p>
        </DetailField>

        <DetailField label="Address">
          <p className="text-sm font-normal text-gray-900">
            {job.gps_address ?? "No address"}
          </p>
        </DetailField>

        {job.tags.length > 0 && (
          <DetailField label="Tags">
            <div className="flex flex-wrap gap-1 mt-1">
              {job.tags.map((tag) => (
                <span
                  key={tag}
                  className="inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-700"
                >
                  {tag}
                </span>
              ))}
            </div>
          </DetailField>
        )}

        <DetailField label="Version">
          <p className="text-sm font-normal text-gray-400">v{job.version}</p>
        </DetailField>
      </CardContent>
    </Card>
  );
}

export function JobFinancialReferencesCard({ job }: { job: Job }) {
  if (!job.purchase_order_number && !job.external_reference) return null;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Financial References</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {job.purchase_order_number && (
          <DetailField label="Purchase Order">
            <p className="text-sm text-gray-900">{job.purchase_order_number}</p>
          </DetailField>
        )}
        {job.external_reference && (
          <DetailField label="External Reference">
            <p className="text-sm text-gray-900">{job.external_reference}</p>
          </DetailField>
        )}
        <p className="text-xs text-gray-400 italic">
          Linked quotes and invoices will appear here in Phase 16.
        </p>
      </CardContent>
    </Card>
  );
}
