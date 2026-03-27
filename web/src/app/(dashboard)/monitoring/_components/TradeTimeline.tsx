"use client";

import dynamic from "next/dynamic";
import { useState, useMemo, useCallback } from "react";
import type { ITask, ILink } from "@svar-ui/react-gantt";
import { useTradeTimeline } from "@/lib/hooks/useDashboard";
import type { TradeTimelineScope, TradeTimelineDep } from "@/lib/types/dashboard";
import { TradeTaskList } from "./TradeTaskList";

// CRITICAL: SSR avoidance — SVAR Gantt uses browser APIs at module load time
const GanttChart = dynamic(
  () => import("@svar-ui/react-gantt").then((mod) => mod.Gantt),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-48 items-center justify-center text-sm text-gray-400">
        Loading Gantt chart...
      </div>
    ),
  }
);

const ONE_DAY_MS = 86_400_000;

function clampPercent(value: number): number {
  return Math.min(100, Math.max(0, value));
}

/** Map trade scopes to SVAR ITask format, filtering out invalid dates. */
function mapScopesToGanttTasks(scopes: TradeTimelineScope[]): ITask[] {
  return scopes
    .filter((scope) => {
      const start = new Date(scope.start_date);
      const end = new Date(scope.end_date);
      return !isNaN(start.getTime()) && !isNaN(end.getTime());
    })
    .map((scope) => {
      const start = new Date(scope.start_date);
      const end = new Date(scope.end_date);
      // Ensure end >= start (min 1 day)
      if (end <= start) end.setTime(start.getTime() + ONE_DAY_MS);
      return {
        id: scope.id,
        text: scope.trade_name,
        start,
        end,
        progress: clampPercent(scope.progress),
        type: "task" as const,
      };
    });
}

/** Map dependencies to SVAR ILink format (finish-to-start). */
function mapDependenciesToGanttLinks(dependencies: TradeTimelineDep[]): ILink[] {
  return dependencies.map((dependency, index) => ({
    id: `link-${index}`,
    source: dependency.source_id,
    target: dependency.target_id,
    type: "e2s" as ILink["type"],
  }));
}

interface TradeTimelineProps {
  projectId: string;
}

export function TradeTimeline({ projectId }: TradeTimelineProps) {
  const { data: timelineData, isLoading, isError } = useTradeTimeline(projectId);
  const [expandedTradeId, setExpandedTradeId] = useState<string | null>(null);

  const ganttTasks = useMemo(
    (): ITask[] => (timelineData?.scopes ? mapScopesToGanttTasks(timelineData.scopes) : []),
    [timelineData]
  );

  const ganttLinks = useMemo(
    (): ILink[] => (timelineData?.dependencies ? mapDependenciesToGanttLinks(timelineData.dependencies) : []),
    [timelineData]
  );

  const handleTaskClick = useCallback((ev: { id?: string | number }) => {
    const id = ev?.id ? String(ev.id) : null;
    setExpandedTradeId((prev) => (prev === id ? null : id));
  }, []);

  const handleCloseTaskList = useCallback(() => setExpandedTradeId(null), []);

  return (
    <div className="rounded-xl border border-gray-200 bg-white shadow-sm overflow-hidden">
      {/* Header */}
      <div className="border-b border-gray-100 px-4 py-3">
        <h2 className="text-sm font-semibold text-gray-900">Trade Timeline</h2>
        <p className="text-xs text-gray-500">
          Click a trade bar to view task details.
        </p>
      </div>

      {/* Gantt chart */}
      <div className="px-2 py-2">
        {isLoading ? (
          <div className="h-48 animate-pulse rounded bg-gray-100" />
        ) : isError ? (
          <p className="py-6 text-center text-sm text-red-500">
            Failed to load timeline.
          </p>
        ) : ganttTasks.length === 0 ? (
          <p className="py-6 text-center text-sm text-gray-500">
            No trade scopes found for this project.
          </p>
        ) : (
          <div className="h-72">
            <GanttChart
              tasks={ganttTasks}
              links={ganttLinks}
              onTaskClick={handleTaskClick}
              readonly={true}
            />
          </div>
        )}
      </div>

      {/* Inline task drill-down */}
      {expandedTradeId && (
        <div className="px-4 pb-4">
          <TradeTaskList
            projectId={projectId}
            tradeScopeId={expandedTradeId}
            onClose={handleCloseTaskList}
          />
        </div>
      )}
    </div>
  );
}
