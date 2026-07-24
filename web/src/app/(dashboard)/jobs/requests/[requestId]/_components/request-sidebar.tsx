import { StatusBadge } from "@/components/shared/status-badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { JobRequestResponse } from "@/types/api";

const FIELD_LABEL_CLASS =
  "text-xs font-semibold text-gray-500 uppercase tracking-wide";

function ClientInfoCard({ request }: { request: JobRequestResponse }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Client Info</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="space-y-4">
          <div>
            <dt className={FIELD_LABEL_CLASS}>Name</dt>
            <dd className="mt-1">
              <p className="text-sm font-medium text-gray-900">
                {request.client_name}
              </p>
            </dd>
          </div>
          {request.client_email && (
            <div>
              <dt className={FIELD_LABEL_CLASS}>Email</dt>
              <dd className="mt-1">
                <a
                  href={`mailto:${request.client_email}`}
                  className="text-sm text-blue-600 hover:underline"
                >
                  {request.client_email}
                </a>
              </dd>
            </div>
          )}
          {request.client_phone && (
            <div>
              <dt className={FIELD_LABEL_CLASS}>Phone</dt>
              <dd className="mt-1">
                <a
                  href={`tel:${request.client_phone}`}
                  className="text-sm text-blue-600 hover:underline"
                >
                  {request.client_phone}
                </a>
              </dd>
            </div>
          )}
        </dl>
      </CardContent>
    </Card>
  );
}

function RequestMetadataCard({ request }: { request: JobRequestResponse }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Request Metadata</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="space-y-4">
          <div>
            <dt className={FIELD_LABEL_CLASS}>Status</dt>
            <dd className="mt-1">
              <StatusBadge status={request.status} />
            </dd>
          </div>
          <div>
            <dt className={FIELD_LABEL_CLASS}>Submitted</dt>
            <dd className="mt-1 text-sm text-gray-900">
              {new Date(request.created_at).toLocaleDateString()}
            </dd>
          </div>
        </dl>
      </CardContent>
    </Card>
  );
}

export function RequestSidebar({ request }: { request: JobRequestResponse }) {
  return (
    <div className="space-y-4">
      <ClientInfoCard request={request} />
      <RequestMetadataCard request={request} />
    </div>
  );
}
