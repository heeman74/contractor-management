"use client";

import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Calendar, Clock, DollarSign, Camera, User, Pencil, Trash2 } from "lucide-react";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { updateTask, deleteTask } from "@/lib/api/projects";
import { TaskPhotos } from "./TaskPhotos";
import type { TaskResponse, TaskUpdate, MaterialItem } from "@/types/projects";

interface TaskDetailProps {
  task: TaskResponse;
  /** Called after the task is deleted so the parent can clear its selection. */
  onTaskDeleted?: () => void;
}

const PRIORITY_OPTIONS = ["low", "medium", "high", "urgent"] as const;
// Task status check constraint: not_started | in_progress | complete | blocked.
// "blocked" is managed by the dependency engine, so it is not offered manually.
const STATUS_OPTIONS = ["not_started", "in_progress", "complete"] as const;

const PRIORITY_COLORS: Record<string, string> = {
  urgent: "bg-red-100 text-red-800",
  high: "bg-orange-100 text-orange-800",
  medium: "bg-yellow-100 text-yellow-800",
  low: "bg-gray-100 text-gray-700",
};

function labelize(value: string): string {
  return value.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function PriorityBadge({ priority }: { priority: string }) {
  const classes =
    PRIORITY_COLORS[priority.toLowerCase()] ?? "bg-gray-100 text-gray-700";
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${classes}`}
    >
      {labelize(priority)}
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
        <li key={idx} className="flex items-center gap-2 text-sm text-gray-700">
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

interface TaskEditForm {
  title: string;
  description: string;
  priority: string;
  status: string;
  estimated_hours: string;
  due_date: string;
}

function toForm(task: TaskResponse): TaskEditForm {
  return {
    title: task.title,
    description: task.description ?? "",
    priority: task.priority,
    status: task.status,
    estimated_hours: task.estimated_hours != null ? String(task.estimated_hours) : "",
    due_date: task.due_date ? task.due_date.slice(0, 10) : "",
  };
}

function toUpdate(form: TaskEditForm): TaskUpdate {
  const hours = form.estimated_hours.trim();
  return {
    title: form.title.trim(),
    description: form.description.trim() || null,
    priority: form.priority,
    status: form.status,
    estimated_hours: hours === "" ? null : Number(hours),
    due_date: form.due_date || null,
  };
}

export function TaskDetail({ task, onTaskDeleted }: TaskDetailProps) {
  const queryClient = useQueryClient();
  // Local copy so saved edits show immediately without re-selecting the task
  // (the parent passes a snapshot captured at selection time).
  const [current, setCurrent] = useState<TaskResponse>(task);
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState<TaskEditForm>(() => toForm(task));
  const [confirmDelete, setConfirmDelete] = useState(false);

  // Reset when a different task is selected.
  useEffect(() => {
    setCurrent(task);
    setForm(toForm(task));
    setIsEditing(false);
    setConfirmDelete(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [task.id]);

  const invalidateTasks = () =>
    queryClient.invalidateQueries({ queryKey: ["tasks", current.trade_scope_id] });

  const saveMutation = useMutation({
    mutationFn: () => updateTask(current.id, toUpdate(form)),
    onSuccess: (updated) => {
      setCurrent(updated);
      setForm(toForm(updated));
      invalidateTasks();
      toast.success("Task updated.");
      setIsEditing(false);
    },
    onError: () => toast.error("Failed to update task. Please try again."),
  });

  const deleteMutation = useMutation({
    mutationFn: () => deleteTask(current.id),
    onSuccess: () => {
      invalidateTasks();
      toast.success("Task deleted.");
      setConfirmDelete(false);
      onTaskDeleted?.();
    },
    onError: () => {
      toast.error("Failed to delete task. Please try again.");
      setConfirmDelete(false);
    },
  });

  const setField = (field: keyof TaskEditForm, value: string) =>
    setForm((prev) => ({ ...prev, [field]: value }));

  const handleSave = () => {
    if (!form.title.trim()) {
      toast.error("Task title is required.");
      return;
    }
    saveMutation.mutate();
  };

  return (
    <div className="flex flex-col gap-6 p-6">
      {/* Header */}
      <div className="flex items-start justify-between gap-4">
        {isEditing ? (
          <div className="flex-1">
            <Label htmlFor="task-title">Title</Label>
            <Input
              id="task-title"
              value={form.title}
              onChange={(e) => setField("title", e.target.value)}
              className="mt-1"
            />
          </div>
        ) : (
          <h2 className="text-xl font-semibold text-gray-900">{current.title}</h2>
        )}
        <div className="flex flex-shrink-0 items-center gap-2">
          {isEditing ? (
            <>
              <Button size="sm" onClick={handleSave} disabled={saveMutation.isPending}>
                {saveMutation.isPending ? "Saving…" : "Save"}
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => {
                  setForm(toForm(current));
                  setIsEditing(false);
                }}
                disabled={saveMutation.isPending}
              >
                Cancel
              </Button>
            </>
          ) : (
            <>
              <PriorityBadge priority={current.priority} />
              <StatusBadge status={current.status} />
              <Button
                size="sm"
                variant="outline"
                onClick={() => setIsEditing(true)}
                aria-label="Edit task"
              >
                <Pencil className="h-3.5 w-3.5" />
                Edit
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setConfirmDelete(true)}
                aria-label="Delete task"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </>
          )}
        </div>
      </div>

      {isEditing ? (
        <div className="flex flex-col gap-4">
          <div>
            <Label htmlFor="task-description">Description</Label>
            <Textarea
              id="task-description"
              value={form.description}
              onChange={(e) => setField("description", e.target.value)}
              rows={3}
              className="mt-1"
            />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>Priority</Label>
              <Select
                value={form.priority}
                onValueChange={(v) => {
                  if (v) setField("priority", v);
                }}
              >
                <SelectTrigger className="mt-1">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {PRIORITY_OPTIONS.map((p) => (
                    <SelectItem key={p} value={p}>
                      {labelize(p)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Status</Label>
              <Select
                value={form.status}
                onValueChange={(v) => {
                  if (v) setField("status", v);
                }}
              >
                <SelectTrigger className="mt-1">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {STATUS_OPTIONS.map((s) => (
                    <SelectItem key={s} value={s}>
                      {labelize(s)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="task-hours">Estimated hours</Label>
              <Input
                id="task-hours"
                type="number"
                min="0"
                step="0.5"
                value={form.estimated_hours}
                onChange={(e) => setField("estimated_hours", e.target.value)}
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="task-due">Due date</Label>
              <Input
                id="task-due"
                type="date"
                value={form.due_date}
                onChange={(e) => setField("due_date", e.target.value)}
                className="mt-1"
              />
            </div>
          </div>
        </div>
      ) : (
        <>
          {current.description && (
            <p className="text-sm text-gray-600">{current.description}</p>
          )}

          {/* Meta grid */}
          <div className="grid grid-cols-2 gap-4 text-sm">
            {current.due_date && (
              <div className="flex items-center gap-2 text-gray-600">
                <Calendar className="h-4 w-4 text-gray-400" />
                <span>Due: {new Date(current.due_date).toLocaleDateString()}</span>
              </div>
            )}
            {current.estimated_hours !== null && (
              <div className="flex items-center gap-2 text-gray-600">
                <Clock className="h-4 w-4 text-gray-400" />
                <span>Est. {current.estimated_hours}h</span>
              </div>
            )}
            {current.estimated_cost !== null && (
              <div className="flex items-center gap-2 text-gray-600">
                <DollarSign className="h-4 w-4 text-gray-400" />
                <span>Est. cost ${current.estimated_cost.toLocaleString()}</span>
              </div>
            )}
            {current.assigned_to && (
              <div className="flex items-center gap-2 text-gray-600">
                <User className="h-4 w-4 text-gray-400" />
                <span>Assigned: {current.assigned_to}</span>
              </div>
            )}
            {current.photo_required && (
              <div className="flex items-center gap-2 text-foreground">
                <Camera className="h-4 w-4" />
                <span className="font-medium">Photo required</span>
              </div>
            )}
          </div>
        </>
      )}

      {/* Materials needed */}
      <div>
        <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-700">
          Materials Needed
        </h3>
        <MaterialsList materials={current.materials_needed} />
      </div>

      {/* Photos — view gallery; managers can add photos / drawings / annotations */}
      <TaskPhotos taskId={current.id} />

      <Dialog open={confirmDelete} onOpenChange={setConfirmDelete}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete this task?</DialogTitle>
            <DialogDescription>
              &ldquo;{current.title}&rdquo; will be permanently removed. This cannot be
              undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setConfirmDelete(false)}
              disabled={deleteMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={() => deleteMutation.mutate()}
              disabled={deleteMutation.isPending}
            >
              {deleteMutation.isPending ? "Deleting…" : "Delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
