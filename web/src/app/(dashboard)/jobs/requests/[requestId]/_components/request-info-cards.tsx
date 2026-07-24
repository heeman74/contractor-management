import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { JobRequestResponse } from "@/types/api";

const FIELD_LABEL_CLASS =
  "text-xs font-semibold text-gray-500 uppercase tracking-wide";

function DescriptionField({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <dt className={FIELD_LABEL_CLASS}>{label}</dt>
      <dd className="mt-1 text-sm text-gray-900">{children}</dd>
    </div>
  );
}

export function RequestDetailsCard({ request }: { request: JobRequestResponse }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Request Details</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="text-sm leading-relaxed text-gray-700">
          {request.description}
        </p>
      </CardContent>
    </Card>
  );
}

export function JobScheduleInfoCard({ request }: { request: JobRequestResponse }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Job &amp; Schedule Info</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="space-y-4">
          <DescriptionField label="Job Type">
            {request.job_type ?? "Not specified"}
          </DescriptionField>
          <DescriptionField label="Preferred Date">
            {request.preferred_date
              ? new Date(request.preferred_date).toLocaleDateString()
              : "Flexible"}
          </DescriptionField>
          <DescriptionField label="Preferred Time">
            {request.preferred_time ?? "Not specified"}
          </DescriptionField>
          <DescriptionField label="Property Address">
            {request.property_address ?? "No address provided"}
          </DescriptionField>
        </dl>
      </CardContent>
    </Card>
  );
}
