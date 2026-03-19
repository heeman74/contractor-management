"use client";

import { Fragment } from "react";
import { type UtilizationHeatmapResponse } from "@/types/api";
import { cn } from "@/lib/utils";

interface UtilizationHeatmapProps {
  data: UtilizationHeatmapResponse;
}

function cellColor(utilPct: number): string {
  if (utilPct >= 85) return "bg-red-500";
  if (utilPct >= 60) return "bg-yellow-400";
  if (utilPct >= 30) return "bg-green-400";
  return "bg-green-200";
}

export function UtilizationHeatmap({ data }: UtilizationHeatmapProps) {
  const { weeks, contractors } = data;

  return (
    <div className="overflow-x-auto">
      <div
        className="grid"
        style={{ gridTemplateColumns: `180px repeat(${weeks.length}, minmax(40px, 1fr))` }}
      >
        {/* Header row */}
        <div /> {/* empty corner cell */}
        {weeks.map((w) => (
          <div key={w} className="text-xs text-center text-muted-foreground truncate px-1">
            {w}
          </div>
        ))}

        {/* Data rows */}
        {contractors.map((c) => {
          // Build lookup: iso_week -> UtilizationWeekItem
          const weekMap = new Map(c.weeks.map((w) => [w.iso_week, w]));
          return (
            <Fragment key={c.contractor_id}>
              <div className="text-sm truncate pr-2 flex items-center h-8">
                {c.contractor_name}
              </div>
              {weeks.map((w) => {
                const cell = weekMap.get(w);
                const pct = cell ? parseFloat(cell.utilization_percent) : 0;
                return (
                  <div
                    key={w}
                    title={`${c.contractor_name} — ${w}: ${pct.toFixed(0)}%`}
                    className={cn(
                      "h-8 rounded-sm mx-1",
                      cell ? cellColor(pct) : "bg-muted"
                    )}
                  />
                );
              })}
            </Fragment>
          );
        })}
      </div>
    </div>
  );
}
