"use client";

import { X } from "lucide-react";
import { useTradeTasks } from "@/lib/hooks/useDashboard";

interface TradeTaskListProps {
  projectId: string;
  tradeScopeId: string;
  onClose: () => void;
}

/** Consistent date formatter — explicit locale & options to avoid cross-browser drift. */
function formatDate(dateStr: string | null): string | null {
  if (!dateStr) return null;
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return null;
  return d.toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

const statusConfig: Record<string, { label: string; className: string }> = {
  complete: { label: "Complete", className: "bg-green-100 text-green-800" },
  completed: { label: "Complete", className: "bg-green-100 text-green-800" },
  in_progress: { label: "In Progress", className: "bg-blue-100 text-blue-800" },
  blocked: { label: "Blocked", className: "bg-red-100 text-red-800" },
  pending: { label: "Pending", className: "bg-gray-100 text-gray-600" },
};

function getStatusConfig(status: string) {
  return statusConfig[status] ?? { label: status, className: "bg-gray-100 text-gray-600" };
}

function isPastDue(dueDateStr: string | null, status: string): boolean {
  if (!dueDateStr) return false;
  if (status === "complete" || status === "completed") return false;
  const d = new Date(dueDateStr);
  if (isNaN(d.getTime())) return false;
  return d < new Date();
}

export function TradeTaskList({ projectId, tradeScopeId, onClose }: TradeTaskListProps) {
  const { data: tasks, isLoading, isError } = useTradeTasks(projectId, tradeScopeId);

  return (
    <div className="mt-3 rounded-xl border border-gray-200 bg-white shadow-sm overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-gray-100 px-4 py-2">
        <h3 className="text-sm font-semibold text-gray-900">Tasks</h3>
        <button
          onClick={onClose}
          className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors"
          aria-label="Close task list"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Task table */}
      <div className="overflow-x-auto">
        {isLoading ? (
          <div className="p-4 space-y-2">
            {[...Array(4)].map((_, i) => (
              <div key={i} className="h-8 animate-pulse rounded bg-gray-100" />
            ))}
          </div>
        ) : isError ? (
          <p className="p-4 text-center text-xs text-red-500">
            Failed to load tasks.
          </p>
        ) : !tasks || tasks.length === 0 ? (
          <p className="p-4 text-center text-sm text-gray-500">
            No tasks found for this trade.
          </p>
        ) : (
          <table className="w-full text-xs" aria-label="Trade tasks">
            <thead className="bg-gray-50 text-gray-500">
              <tr>
                <th className="px-3 py-2 text-left font-medium">Title</th>
                <th className="px-3 py-2 text-left font-medium">Status</th>
                <th className="px-3 py-2 text-left font-medium">Assignee</th>
                <th className="px-3 py-2 text-left font-medium">Start Date</th>
                <th className="px-3 py-2 text-left font-medium">Due Date</th>
                <th className="px-3 py-2 text-left font-medium">Dependencies</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {tasks.map((task) => {
                const status = getStatusConfig(task.status);
                const pastDue = isPastDue(task.due_date, task.status);
                return (
                  <tr key={task.task_id} className="hover:bg-gray-50">
                    <td className="px-3 py-2 text-gray-900 font-medium">
                      {task.title}
                    </td>
                    <td className="px-3 py-2">
                      <span
                        className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${status.className}`}
                      >
                        {status.label}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-gray-600">
                      {task.assignee_name ?? <span className="text-gray-400">—</span>}
                    </td>
                    <td className="px-3 py-2 text-gray-600">
                      {formatDate(task.start_date) ?? <span className="text-gray-400">—</span>}
                    </td>
                    <td
                      className={`px-3 py-2 ${
                        pastDue ? "text-red-600 font-medium" : "text-gray-600"
                      }`}
                    >
                      {formatDate(task.due_date) ?? <span className="text-gray-400">—</span>}
                    </td>
                    <td className="px-3 py-2 text-gray-600">
                      {task.dependency_status ?? <span className="text-gray-400">—</span>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
