"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import Link from "next/link";
import { Bot } from "lucide-react";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { useTasks, updateTradeScope } from "@/lib/api/projects";
import type { TradeScopeResponse } from "@/types/projects";

interface TradeScopeDetailProps {
  scope: TradeScopeResponse;
  onSelectTask: (taskId: string) => void;
}

const PRIORITY_BORDER: Record<string, string> = {
  urgent: "border-l-red-500",
  high: "border-l-orange-400",
  medium: "border-l-yellow-400",
  low: "border-l-gray-200",
};

export function TradeScopeDetail({ scope, onSelectTask }: TradeScopeDetailProps) {
  const queryClient = useQueryClient();
  const { data: tasks } = useTasks(scope.id);
  const [overrideMode, setOverrideMode] = useState(false);

  const completedCount = tasks?.filter((t) => t.status === "complete" || t.status === "approved").length ?? 0;
  const totalCount = tasks?.length ?? 0;
  const progressPercent = totalCount > 0 ? Math.round((completedCount / totalCount) * 100) : 0;

  const updateStatusMutation = useMutation({
    mutationFn: (newStatus: string) =>
      updateTradeScope(scope.id, { trade_name: scope.trade_name }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["trade-scopes", scope.project_id] });
      toast.success("Status updated.");
      setOverrideMode(false);
    },
    onError: () => {
      toast.error("Failed to update status.");
    },
  });

  const statusOptions = ["not_started", "in_progress", "complete", "on_hold"];

  return (
    <div className="flex flex-col gap-6 p-6">
      {/* Header */}
      <div className="flex items-start justify-between gap-4">
        <div className="flex items-center gap-3">
          {/* 12px color swatch */}
          <span
            className="inline-block h-4 w-4 flex-shrink-0 rounded-full"
            style={{ backgroundColor: scope.trade_color || "#6b7280" }}
            aria-hidden="true"
          />
          <h2 className="text-xl font-semibold text-gray-900">{scope.trade_name}</h2>
        </div>
        <div className="flex items-center gap-2">
          {overrideMode ? (
            <div className="flex items-center gap-2">
              {statusOptions.map((s) => (
                <button
                  key={s}
                  onClick={() => updateStatusMutation.mutate(s)}
                  className="rounded-md px-2 py-1 text-xs border border-gray-200 hover:bg-gray-100"
                >
                  {s.replace(/_/g, " ")}
                </button>
              ))}
              <Button
                variant="outline"
                size="sm"
                onClick={() => setOverrideMode(false)}
              >
                Cancel
              </Button>
            </div>
          ) : (
            <button
              onClick={() => setOverrideMode(true)}
              title="Click to override status"
              className="cursor-pointer rounded focus:outline-none focus:ring-2 focus:ring-indigo-500"
              aria-label="Override status"
            >
              <StatusBadge status={scope.status} />
            </button>
          )}
        </div>
      </div>

      {/* Contractor */}
      <div className="text-sm text-gray-600">
        <span className="font-medium text-gray-700">Contractor:</span>{" "}
        {scope.contractor_id ? scope.contractor_id : "Unassigned"}
      </div>

      {/* Task progress */}
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between text-sm">
          <span className="font-medium text-gray-700">Task Progress</span>
          <span className="text-gray-500">
            {completedCount}/{totalCount} completed
          </span>
        </div>
        <div className="h-2 w-full overflow-hidden rounded-full bg-gray-100">
          <div
            className="h-2 rounded-full bg-indigo-500 transition-all"
            style={{ width: `${progressPercent}%` }}
            role="progressbar"
            aria-valuenow={progressPercent}
            aria-valuemin={0}
            aria-valuemax={100}
          />
        </div>
      </div>

      {/* Task list */}
      <div>
        <div className="mb-3 flex items-center justify-between">
          <h3 className="text-sm font-semibold uppercase tracking-wide text-gray-700">
            Tasks ({totalCount})
          </h3>
          {totalCount === 0 && (
            <Link
              href={`/projects/${scope.project_id}/interview/${scope.id}`}
              className="inline-flex h-7 items-center gap-1 rounded-[min(var(--radius-md),12px)] border border-border bg-background px-2.5 text-[0.8rem] font-medium text-foreground transition-colors hover:bg-muted"
            >
              <Bot className="h-3.5 w-3.5" />
              Start AI Interview
            </Link>
          )}
        </div>
        {tasks && tasks.length > 0 ? (
          <div className="space-y-2">
            {tasks.map((task) => {
              const borderColor = PRIORITY_BORDER[task.priority] ?? "border-l-gray-200";
              return (
                <div
                  key={task.id}
                  className={`flex cursor-pointer items-center justify-between gap-3 rounded-lg border border-gray-200 border-l-4 bg-white p-3 transition-colors hover:bg-gray-50 ${borderColor}`}
                  onClick={() => onSelectTask(task.id)}
                  role="button"
                  tabIndex={0}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      onSelectTask(task.id);
                    }
                  }}
                >
                  <span className="text-sm font-medium text-gray-800">
                    {task.title}
                  </span>
                  <StatusBadge status={task.status} size="sm" />
                </div>
              );
            })}
          </div>
        ) : (
          <p className="text-sm text-gray-500">No tasks yet.</p>
        )}
      </div>
    </div>
  );
}
