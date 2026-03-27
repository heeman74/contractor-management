"use client";

import { memo } from "react";
import { AlertTriangle } from "lucide-react";
import { cn, clampPercent } from "@/lib/utils";
import type { ProjectStatusCardData } from "@/lib/types/dashboard";
import { TradeStatusBadge } from "./TradeStatusBadge";

interface ProjectStatusCardProps {
  project: ProjectStatusCardData;
  isSelected: boolean;
  onSelect: (projectId: string) => void;
}

export const ProjectStatusCard = memo(function ProjectStatusCard({
  project,
  isSelected,
  onSelect,
}: ProjectStatusCardProps) {
  const clampedPct = clampPercent(project.overall_completion_pct);

  return (
    <button
      onClick={() => onSelect(project.project_id)}
      className={cn(
        "w-full text-left rounded-xl bg-white border p-4 shadow-sm hover:shadow-md transition-all focus:outline-none",
        isSelected
          ? "ring-2 ring-indigo-500 border-indigo-500"
          : "border-gray-200 hover:border-indigo-300"
      )}
      aria-pressed={isSelected}
    >
      {/* Header: project name + status badge */}
      <div className="flex items-start justify-between gap-2 mb-3">
        <h3 className="text-sm font-semibold text-gray-900 leading-tight line-clamp-2">
          {project.project_name}
        </h3>
        <span className="inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-600 flex-shrink-0 capitalize">
          {project.status.replace(/_/g, " ")}
        </span>
      </div>

      {/* Overall progress bar */}
      <div className="mb-1 flex items-center justify-between text-xs text-gray-500">
        <span>Overall progress</span>
        <span>{project.overall_completion_pct}%</span>
      </div>
      <div
        className="h-2 rounded-full bg-gray-100 overflow-hidden mb-3"
        role="progressbar"
        aria-valuenow={clampedPct}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={`Overall progress: ${clampedPct}%`}
      >
        <div
          className="h-full rounded-full bg-indigo-500 transition-all"
          style={{ width: `${clampedPct}%` }}
        />
      </div>

      {/* Per-trade status badges */}
      {project.trade_statuses.length > 0 && (
        <div className="space-y-0.5 mb-3">
          {project.trade_statuses.map((badge) => (
            <TradeStatusBadge key={badge.trade_scope_id} badge={badge} />
          ))}
        </div>
      )}

      {/* Alert count */}
      {project.active_alert_count > 0 && (
        <div className="mt-2 flex items-center gap-1 text-xs text-red-600 font-medium">
          <AlertTriangle className="h-3.5 w-3.5" />
          <span>
            {project.active_alert_count} alert
            {project.active_alert_count !== 1 ? "s" : ""}
          </span>
        </div>
      )}
    </button>
  );
});
