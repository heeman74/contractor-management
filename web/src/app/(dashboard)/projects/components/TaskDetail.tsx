"use client";

import { Calendar, Clock, DollarSign, Camera, User } from "lucide-react";
import { StatusBadge } from "@/components/shared/status-badge";
import type { TaskResponse, MaterialItem } from "@/types/projects";

interface TaskDetailProps {
  task: TaskResponse;
}

const PRIORITY_COLORS: Record<string, string> = {
  urgent: "bg-red-100 text-red-800",
  high: "bg-orange-100 text-orange-800",
  medium: "bg-yellow-100 text-yellow-800",
  low: "bg-gray-100 text-gray-700",
};

function PriorityBadge({ priority }: { priority: string }) {
  const classes =
    PRIORITY_COLORS[priority.toLowerCase()] ?? "bg-gray-100 text-gray-700";
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${classes}`}
    >
      {priority.charAt(0).toUpperCase() + priority.slice(1)}
    </span>
  );
}

function MaterialsList({ materials }: { materials: MaterialItem[] }) {
  if (!materials || materials.length === 0) {
    return <span className="text-sm text-gray-500">None</span>;
  }
  return (
    <ul className="space-y-1">
      {materials.map((item, idx) => (
        <li
          key={idx}
          className="flex items-center gap-2 text-sm text-gray-700"
        >
          <span className="inline-block h-1.5 w-1.5 rounded-full bg-gray-400" />
          {item.name}{" "}
          <span className="text-gray-500">
            &times; {item.quantity} {item.unit}
          </span>
        </li>
      ))}
    </ul>
  );
}

export function TaskDetail({ task }: TaskDetailProps) {
  return (
    <div className="flex flex-col gap-6 p-6">
      {/* Header */}
      <div className="flex items-start justify-between gap-4">
        <h2 className="text-xl font-semibold text-gray-900">{task.title}</h2>
        <div className="flex flex-shrink-0 items-center gap-2">
          <PriorityBadge priority={task.priority} />
          <StatusBadge status={task.status} />
        </div>
      </div>

      {/* Description */}
      {task.description && (
        <p className="text-sm text-gray-600">{task.description}</p>
      )}

      {/* Meta grid */}
      <div className="grid grid-cols-2 gap-4 text-sm">
        {task.due_date && (
          <div className="flex items-center gap-2 text-gray-600">
            <Calendar className="h-4 w-4 text-gray-400" />
            <span>
              Due: {new Date(task.due_date).toLocaleDateString()}
            </span>
          </div>
        )}
        {task.estimated_hours !== null && (
          <div className="flex items-center gap-2 text-gray-600">
            <Clock className="h-4 w-4 text-gray-400" />
            <span>Est. {task.estimated_hours}h</span>
          </div>
        )}
        {task.estimated_cost !== null && (
          <div className="flex items-center gap-2 text-gray-600">
            <DollarSign className="h-4 w-4 text-gray-400" />
            <span>
              Est. cost ${task.estimated_cost.toLocaleString()}
            </span>
          </div>
        )}
        {task.assigned_to && (
          <div className="flex items-center gap-2 text-gray-600">
            <User className="h-4 w-4 text-gray-400" />
            <span>Assigned: {task.assigned_to}</span>
          </div>
        )}
        {task.photo_required && (
          <div className="flex items-center gap-2 text-indigo-600">
            <Camera className="h-4 w-4" />
            <span className="font-medium">Photo required</span>
          </div>
        )}
      </div>

      {/* Materials needed */}
      <div>
        <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-700">
          Materials Needed
        </h3>
        <MaterialsList materials={task.materials_needed} />
      </div>

      {/* Dependencies are now managed via the Gantt timeline view */}
    </div>
  );
}
