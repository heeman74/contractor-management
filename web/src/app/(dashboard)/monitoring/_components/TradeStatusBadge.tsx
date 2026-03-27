import { memo } from "react";
import { clampPercent } from "@/lib/utils";
import type { TradeStatusBadgeData } from "@/lib/types/dashboard";

interface TradeStatusBadgeProps {
  badge: TradeStatusBadgeData;
}

const statusConfig = {
  on_track: {
    label: "On Track",
    pillClass: "bg-green-100 text-green-800",
  },
  at_risk: {
    label: "At Risk",
    pillClass: "bg-amber-100 text-amber-800",
  },
  blocked: {
    label: "Blocked",
    pillClass: "bg-red-100 text-red-800",
  },
} as const;

export const TradeStatusBadge = memo(function TradeStatusBadge({ badge }: TradeStatusBadgeProps) {
  const config = statusConfig[badge.status] ?? statusConfig.on_track;
  const clampedPct = clampPercent(badge.completion_pct);

  return (
    <div className="flex items-center gap-2 py-1">
      {/* Trade name */}
      <span className="w-32 flex-shrink-0 truncate text-xs text-gray-700 font-medium">
        {badge.trade_name}
      </span>

      {/* Mini progress bar */}
      <div
        className="flex-1 h-1.5 rounded-full bg-gray-100 overflow-hidden"
        role="progressbar"
        aria-valuenow={clampedPct}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={`${badge.trade_name} progress: ${clampedPct}%`}
      >
        <div
          className="h-full rounded-full bg-indigo-500 transition-all"
          style={{ width: `${clampedPct}%` }}
        />
      </div>

      {/* Completion percentage */}
      <span className="w-8 text-right text-xs text-gray-500 flex-shrink-0">
        {badge.completion_pct}%
      </span>

      {/* Status pill */}
      <span
        className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium flex-shrink-0 ${config.pillClass}`}
      >
        {config.label}
      </span>

      {/* Task count */}
      <span className="text-xs text-gray-400 flex-shrink-0 ml-1">
        {badge.completed_count}/{badge.task_count}
      </span>
    </div>
  );
});
