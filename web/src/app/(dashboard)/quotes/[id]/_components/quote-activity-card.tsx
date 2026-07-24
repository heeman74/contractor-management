import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDateTime } from "@/lib/format";
import type { QuoteActivityEvent } from "../_lib/quote-activity";

export function QuoteActivityCard({
  events,
}: {
  events: QuoteActivityEvent[];
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Activity</CardTitle>
      </CardHeader>
      <CardContent>
        {events.length === 0 ? (
          <p className="text-sm text-gray-500">No activity yet.</p>
        ) : (
          <ul className="space-y-3">
            {events.map((event, idx) => (
              <li key={idx} className="flex items-start gap-3">
                <StatusBadge status={event.status} size="sm" />
                <div className="flex-1 min-w-0">
                  <div className="text-xs text-gray-500">
                    {formatDateTime(event.date)}
                  </div>
                  <div className="text-sm text-gray-700">{event.label}</div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
