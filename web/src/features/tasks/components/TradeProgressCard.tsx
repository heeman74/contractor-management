"use client";

import { CheckCircle } from "lucide-react";
import { cn } from "@/lib/utils";

interface TradeProgressCardProps {
  tradeName: string;
  tradeColor: string;
  completedTasks: number;
  totalTasks: number;
  contractorName?: string;
  lastActivity?: string;
  onClick: () => void;
}

/**
 * GC progress card for a single trade scope (web version).
 *
 * Displays:
 * - Colored dot + trade name + task count
 * - Progress bar with color thresholds:
 *   - 0–33%: purple (bg-purple-600)
 *   - 34–66%: blue (bg-blue-600)
 *   - 67–99%: sky (bg-sky-500)
 *   - 100%: green (bg-green-600)
 * - Contractor name and last activity timestamp
 *
 * Matches the mobile TradeProgressCard layout and color thresholds.
 */
export function TradeProgressCard({
  tradeName,
  tradeColor,
  completedTasks,
  totalTasks,
  contractorName,
  lastActivity,
  onClick,
}: TradeProgressCardProps) {
  const percentage = totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0;
  const isComplete = totalTasks > 0 && completedTasks === totalTasks;
  const isEmpty = totalTasks === 0;

  const progressBarColor = getProgressColor(percentage);

  return (
    <div
      className="cursor-pointer rounded-xl border border-gray-200 bg-white p-4 shadow-sm transition-shadow hover:shadow-md"
      onClick={onClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onClick();
        }
      }}
      aria-label={`${tradeName}: ${completedTasks} of ${totalTasks} tasks complete`}
    >
      {/* Row 1: color dot + trade name + task count + checkmark */}
      <div className="mb-2 flex items-center gap-2">
        <span
          className="inline-block h-3 w-3 flex-shrink-0 rounded-full"
          style={{ backgroundColor: tradeColor || "#6b7280" }}
          aria-hidden="true"
        />
        <span className="flex-1 truncate text-base font-semibold text-gray-900">
          {tradeName}
        </span>
        {isComplete && (
          <CheckCircle className="h-4 w-4 flex-shrink-0 text-green-600" aria-hidden="true" />
        )}
        <span className="flex-shrink-0 text-xs text-gray-500">
          {completedTasks}/{totalTasks} tasks
        </span>
      </div>

      {/* Row 2: progress bar */}
      {isEmpty ? (
        <p className="mb-2 text-xs italic text-gray-400">No activity yet</p>
      ) : (
        <div className="mb-2 h-1.5 w-full overflow-hidden rounded-full bg-gray-100">
          <div
            className={cn("h-full rounded-full transition-all", progressBarColor)}
            style={{ width: `${Math.min(percentage, 100)}%` }}
            role="progressbar"
            aria-valuenow={Math.round(percentage)}
            aria-valuemin={0}
            aria-valuemax={100}
            aria-label={`${completedTasks} of ${totalTasks} tasks complete`}
          />
        </div>
      )}

      {/* Row 3: contractor name + last activity */}
      <div className="flex items-center justify-between">
        {contractorName ? (
          <span className="truncate text-xs font-semibold text-gray-700">
            {abbreviateName(contractorName)}
          </span>
        ) : (
          <span className="text-xs italic text-gray-400">
            No contractor assigned
          </span>
        )}
        {lastActivity && (
          <span className="flex-shrink-0 text-xs text-gray-400">{lastActivity}</span>
        )}
      </div>
    </div>
  );
}

/**
 * Returns a Tailwind background color class for a progress percentage.
 *
 * Thresholds per UI-SPEC:
 * - 0–33%: purple-600
 * - 34–66%: blue-600
 * - 67–99%: sky-500
 * - 100%: green-600
 */
function getProgressColor(percentage: number): string {
  if (percentage >= 100) return "bg-green-600";
  if (percentage >= 67) return "bg-sky-500";
  if (percentage >= 34) return "bg-blue-600";
  return "bg-purple-600";
}

/**
 * Abbreviates a full name to "First L." format.
 * e.g. "John Doe" → "John D."
 */
function abbreviateName(name: string): string {
  const parts = name.trim().split(" ");
  if (parts.length >= 2) {
    return `${parts[0]} ${parts[1][0].toUpperCase()}.`;
  }
  return name;
}
