import type { Job, StatusHistoryEntry } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDateTime } from "@/lib/format";

interface JobActivityCardProps {
  statusHistory: Job["status_history"];
}

const EVENT_LABELS: Record<string, string> = {
  quote_created: "Quote created",
  quote_sent: "Quote sent",
  quote_viewed: "Quote viewed",
  quote_approved: "Quote approved",
  quote_declined: "Quote declined",
  quote_revised: "Quote revised",
  invoice_generated: "Invoice generated",
  delay: "Delay reported",
};

function eventLabel(type: string): string {
  return EVENT_LABELS[type] ?? type.replace(/_/g, " ");
}

// status_history mixes status transitions ({status,...}) with audit events
// ({type,...}). Discriminate on the `status` field to render each correctly.
function isStatusChange(
  entry: StatusHistoryEntry
): entry is Extract<StatusHistoryEntry, { status: string }> {
  return "status" in entry;
}

export function JobActivityCard({ statusHistory }: JobActivityCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Activity</CardTitle>
      </CardHeader>
      <CardContent>
        {statusHistory.length === 0 ? (
          <p className="text-sm text-gray-500">No status history yet.</p>
        ) : (
          <ul className="space-y-3">
            {statusHistory.map((entry, index) => (
              <li key={index} className="flex items-start gap-3">
                {isStatusChange(entry) ? (
                  <StatusBadge status={entry.status} size="sm" />
                ) : (
                  <span className="inline-flex items-center rounded-sm border border-black/5 bg-slate-100 px-1.5 py-0.5 text-[10px] font-mono font-semibold uppercase tracking-wide text-slate-600">
                    {eventLabel(entry.type)}
                  </span>
                )}
                <div className="flex-1 min-w-0">
                  <div className="text-xs text-gray-500">
                    {formatDateTime(entry.timestamp)}
                  </div>
                  {entry.reason && (
                    <div className="text-xs text-gray-400 mt-0.5">
                      Reason: {entry.reason}
                    </div>
                  )}
                  {!isStatusChange(entry) && entry.new_eta && (
                    <div className="text-xs text-gray-400 mt-0.5">
                      New ETA: {formatDateTime(entry.new_eta)}
                    </div>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
