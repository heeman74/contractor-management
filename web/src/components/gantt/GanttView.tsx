"use client";

import dynamic from "next/dynamic";
import { useState, useCallback, useMemo, useRef } from "react";
import type { ITask, ILink } from "@svar-ui/react-gantt";
import type { TradeScopeResponse } from "@/types/projects";
import type { TaskDependencyResponse, ConflictRecord } from "@/types/dependencies";
import { DependencyTypeSelect } from "./DependencyTypeSelect";
import type { DependencyType } from "./DependencyTypeSelect";

// Lazy-load the heavy SVAR Gantt library (avoids SSR issues)
const GanttChart = dynamic(
  () => import("@svar-ui/react-gantt").then((mod) => mod.Gantt),
  { ssr: false, loading: () => <div className="h-full flex items-center justify-center text-gray-400 text-sm">Loading Gantt chart...</div> }
);

// Map our backend dependency types to SVAR link types
function toSvarLinkType(depType: string): string {
  switch (depType) {
    case "FS": return "e2s"; // Finish to Start
    case "SS": return "s2s"; // Start to Start
    case "FF": return "e2e"; // Finish to Finish
    case "SE": return "s2e"; // Start to End
    default: return "e2s";
  }
}


function taskProgress(status: string): number {
  if (status === "complete" || status === "completed") return 100;
  if (status === "in_progress") return 50;
  return 0;
}

export interface PendingLink {
  source: string;
  target: string;
  svarType: string;
}

export interface GanttViewProps {
  projectId: string;
  scopes: TradeScopeResponse[];
  dependencies: TaskDependencyResponse[];
  conflicts: ConflictRecord[];
  onDependencyCreate: (source: string, target: string, type: DependencyType, lagDays: number) => Promise<void>;
  onTaskUpdate: (taskId: string, start: Date, end: Date) => Promise<void>;
}

export function GanttView({
  scopes,
  dependencies,
  conflicts,
  onDependencyCreate,
  onTaskUpdate,
}: GanttViewProps) {
  const [zoomLevel, setZoomLevel] = useState<number>(1); // 0=day, 1=week, 2=month
  const [pendingLink, setPendingLink] = useState<PendingLink | null>(null);
  const [depSelectPos, setDepSelectPos] = useState<{ x: number; y: number } | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // Conflict task IDs for styling
  const conflictTaskIds = useMemo(() => {
    const ids = new Set<string>();
    for (const c of conflicts) {
      ids.add(c.task1_id);
      ids.add(c.task2_id);
    }
    return ids;
  }, [conflicts]);

  // Transform API data into SVAR Gantt tasks
  // Note: SVAR uses the `css` key on ITask for custom class names
  const ganttTasks = useMemo((): ITask[] => {
    const tasks: ITask[] = [];

    for (const scope of scopes) {
      // Summary row for each trade scope
      tasks.push({
        id: scope.id,
        text: scope.trade_name,
        type: "summary",
        open: true,
        color: scope.trade_color,
      });

      for (const task of scope.tasks ?? []) {
        const start = new Date(task.start_date || task.due_date || task.created_at);
        const end = new Date(task.due_date || task.created_at);

        // Ensure end >= start (min 1 day)
        if (end <= start) end.setTime(start.getTime() + 24 * 60 * 60 * 1000);

        // Determine css class for conflict highlighting
        let cssClass: string | undefined;
        if (conflictTaskIds.has(task.id)) {
          cssClass = "gantt-task-conflict";
        }

        tasks.push({
          id: task.id,
          text: task.title,
          parent: scope.id,
          start,
          end,
          progress: taskProgress(task.status),
          type: "task",
          ...(cssClass ? { css: cssClass } : {}),
        });
      }
    }

    return tasks;
  }, [scopes, conflictTaskIds]);

  // Transform API dependencies into SVAR links
  const ganttLinks = useMemo((): ILink[] => {
    return dependencies.map((dep) => ({
      id: dep.id,
      source: dep.predecessor_task_id,
      target: dep.successor_task_id,
      type: toSvarLinkType(dep.dependency_type) as ILink["type"],
      lag: dep.lag_days,
    }));
  }, [dependencies]);

  // Zoom config levels: Day=0, Week=1, Month=2
  const zoomConfig = useMemo(() => ({
    level: zoomLevel,
    levels: [
      {
        minCellWidth: 40,
        maxCellWidth: 80,
        scales: [
          { unit: "month", step: 1, format: "MMMM yyyy" },
          { unit: "day", step: 1, format: "d" },
        ],
      },
      {
        minCellWidth: 60,
        maxCellWidth: 120,
        scales: [
          { unit: "month", step: 1, format: "MMMM yyyy" },
          { unit: "week", step: 1, format: "w" },
        ],
      },
      {
        minCellWidth: 80,
        maxCellWidth: 160,
        scales: [
          { unit: "year", step: 1, format: "yyyy" },
          { unit: "month", step: 1, format: "MMM" },
        ],
      },
    ],
  }), [zoomLevel]);

  // Handle link add event from SVAR (onAddLink maps from "add-link" action)
  const handleAddLink = useCallback((ev: { link: { source?: string | number; target?: string | number; type?: string } }) => {
    const link = ev.link || {};
    setPendingLink({
      source: String(link.source ?? ""),
      target: String(link.target ?? ""),
      svarType: String(link.type ?? "e2s"),
    });
    // Position the popover in the center of the viewport
    setDepSelectPos({ x: 200, y: 200 });
  }, []);

  // Handle task update event from SVAR (onUpdateTask maps from "update-task" action)
  const handleUpdateTask = useCallback((ev: { id: string | number; task: { start?: Date; end?: Date } }) => {
    const { id, task } = ev;
    if (task.start && task.end) {
      onTaskUpdate(String(id), task.start, task.end);
    }
  }, [onTaskUpdate]);

  const handleDepConfirm = useCallback(async (type: DependencyType, lagDays: number) => {
    if (!pendingLink) return;
    await onDependencyCreate(pendingLink.source, pendingLink.target, type, lagDays);
    setPendingLink(null);
    setDepSelectPos(null);
  }, [pendingLink, onDependencyCreate]);

  const handleDepCancel = useCallback(() => {
    setPendingLink(null);
    setDepSelectPos(null);
  }, []);

  // Today marker
  const markers = useMemo(() => [
    { start: new Date(), text: "Today", css: "background: rgba(99,102,241,0.15); border-left: 2px solid #6366f1;" },
  ], []);

  const zoomLabels = ["Day", "Week", "Month"];

  return (
    <div className="flex flex-col h-full" ref={containerRef}>
      {/* Zoom controls */}
      <div className="flex items-center gap-1 px-4 py-2 border-b border-gray-200 bg-white">
        <span className="text-xs text-gray-500 mr-2">Zoom:</span>
        {zoomLabels.map((label, idx) => (
          <button
            key={label}
            onClick={() => setZoomLevel(idx)}
            className={`px-3 py-1 text-xs rounded-md border transition-colors ${
              zoomLevel === idx
                ? "bg-indigo-600 text-white border-indigo-600"
                : "text-gray-600 border-gray-300 hover:bg-gray-100"
            }`}
            aria-pressed={zoomLevel === idx}
            data-zoom={label.toLowerCase()}
          >
            {label}
          </button>
        ))}
      </div>

      {/* Gantt chart */}
      <div className="flex-1 relative overflow-hidden">
        <GanttChart
          tasks={ganttTasks}
          links={ganttLinks}
          zoom={zoomConfig}
          markers={markers}
          onAddLink={handleAddLink}
          onUpdateTask={handleUpdateTask}
        />

        {/* Dependency type popover */}
        {pendingLink && depSelectPos && (
          <div
            className="absolute z-50 bg-white rounded-lg shadow-lg border border-gray-200"
            style={{ top: depSelectPos.y, left: depSelectPos.x }}
          >
            <DependencyTypeSelect
              onConfirm={handleDepConfirm}
              onCancel={handleDepCancel}
            />
          </div>
        )}
      </div>
    </div>
  );
}
