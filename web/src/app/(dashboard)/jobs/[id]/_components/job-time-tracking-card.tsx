import { useState } from "react";
import type { TimeEntryResponse } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDateTime, formatDurationMinutes } from "@/lib/format";

interface JobTimeTrackingCardProps {
  timeEntries: TimeEntryResponse[];
  totalMinutes: number;
}

export function JobTimeTrackingCard({
  timeEntries,
  totalMinutes,
}: JobTimeTrackingCardProps) {
  const [showAll, setShowAll] = useState(false);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Time Tracking</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {timeEntries.length === 0 ? (
          <p className="text-sm text-gray-500">
            No time entries recorded for this job.
          </p>
        ) : (
          <>
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                Total Time
              </span>
              <span className="text-sm font-medium text-gray-900">
                {formatDurationMinutes(totalMinutes)}
              </span>
            </div>
            <button
              className="text-xs text-foreground hover:underline"
              onClick={() => setShowAll((v) => !v)}
            >
              {showAll ? "Hide entries" : `Show ${timeEntries.length} entries`}
            </button>
            {showAll && (
              <ul className="space-y-2 mt-2">
                {timeEntries.map((entry) => (
                  <li key={entry.id} className="text-xs text-gray-600">
                    <span>{formatDateTime(entry.clock_in)}</span>
                    <span className="mx-1">—</span>
                    <span>
                      {entry.clock_out
                        ? formatDateTime(entry.clock_out)
                        : "In progress"}
                    </span>
                    {entry.duration_minutes != null && (
                      <span className="ml-1 text-gray-400">
                        ({formatDurationMinutes(entry.duration_minutes)})
                      </span>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
