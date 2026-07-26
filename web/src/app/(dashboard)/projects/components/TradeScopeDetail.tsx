"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import Link from "next/link";
import { Bot, Plus, Trash2 } from "lucide-react";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  useTasks,
  updateTradeScope,
  createTask,
  deleteTask,
} from "@/lib/api/projects";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { useCostEntriesForTradeScope } from "@/features/finance/hooks";
import { AddCostDialog } from "@/features/finance/components/AddCostDialog";
import { CostEntryList } from "@/features/finance/components/CostEntryList";
import type { TradeScopeResponse, TaskResponse } from "@/types/projects";

interface TradeScopeDetailProps {
  scope: TradeScopeResponse;
  onSelectTask: (task: TaskResponse) => void;
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
  const { can } = usePermissions();
  const { data: costEntries } = useCostEntriesForTradeScope(scope.id);
  const [addCostOpen, setAddCostOpen] = useState(false);

  const completedCount = tasks?.filter((t) => t.status === "complete" || t.status === "approved").length ?? 0;
  const totalCount = tasks?.length ?? 0;
  const progressPercent = totalCount > 0 ? Math.round((completedCount / totalCount) * 100) : 0;

  const updateStatusMutation = useMutation({
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
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

  const [addingTask, setAddingTask] = useState(false);
  const [newTaskTitle, setNewTaskTitle] = useState("");
  const [pendingDeleteTask, setPendingDeleteTask] = useState<TaskResponse | null>(
    null
  );

  const invalidateTasks = () =>
    queryClient.invalidateQueries({ queryKey: ["tasks", scope.id] });

  const createTaskMutation = useMutation({
    mutationFn: (title: string) => createTask({ trade_scope_id: scope.id, title }),
    onSuccess: () => {
      invalidateTasks();
      toast.success("Task added.");
      setNewTaskTitle("");
      setAddingTask(false);
    },
    onError: () => toast.error("Failed to add task. Please try again."),
  });

  const deleteTaskMutation = useMutation({
    mutationFn: (taskId: string) => deleteTask(taskId),
    onSuccess: () => {
      invalidateTasks();
      toast.success("Task deleted.");
      setPendingDeleteTask(null);
    },
    onError: () => {
      toast.error("Failed to delete task. Please try again.");
      setPendingDeleteTask(null);
    },
  });

  const handleAddTask = () => {
    const title = newTaskTitle.trim();
    if (!title) return;
    createTaskMutation.mutate(title);
  };

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
              className="cursor-pointer rounded focus:outline-none focus:ring-2 focus:ring-ring"
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
            className="h-2 rounded-full bg-brand transition-all"
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
          <div className="flex items-center gap-2">
            {totalCount === 0 && (
              <Link
                href={`/projects/${scope.project_id}/interview/${scope.id}`}
                className="inline-flex h-7 items-center gap-1 rounded-[min(var(--radius-md),12px)] border border-border bg-background px-2.5 text-[0.8rem] font-medium text-foreground transition-colors hover:bg-muted"
              >
                <Bot className="h-3.5 w-3.5" />
                Start AI Interview
              </Link>
            )}
            <Button
              size="sm"
              variant="outline"
              onClick={() => setAddingTask(true)}
              data-testid="add-task-button"
            >
              <Plus className="h-3.5 w-3.5" />
              Add task
            </Button>
          </div>
        </div>

        {addingTask && (
          <div className="mb-3 flex items-center gap-2">
            <Input
              autoFocus
              value={newTaskTitle}
              onChange={(e) => setNewTaskTitle(e.target.value)}
              placeholder="Task title"
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  handleAddTask();
                }
                if (e.key === "Escape") {
                  setAddingTask(false);
                  setNewTaskTitle("");
                }
              }}
            />
            <Button
              size="sm"
              onClick={handleAddTask}
              disabled={createTaskMutation.isPending || !newTaskTitle.trim()}
            >
              {createTaskMutation.isPending ? "Adding…" : "Add"}
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                setAddingTask(false);
                setNewTaskTitle("");
              }}
            >
              Cancel
            </Button>
          </div>
        )}
        {tasks && tasks.length > 0 ? (
          <div className="space-y-2">
            {tasks.map((task) => {
              const borderColor = PRIORITY_BORDER[task.priority] ?? "border-l-gray-200";
              return (
                <div
                  key={task.id}
                  className={`flex cursor-pointer items-center justify-between gap-3 rounded-lg border border-gray-200 border-l-4 bg-white p-3 transition-colors hover:bg-gray-50 ${borderColor}`}
                  onClick={() => onSelectTask(task)}
                  role="button"
                  tabIndex={0}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      onSelectTask(task);
                    }
                  }}
                >
                  <span className="text-sm font-medium text-gray-800">
                    {task.title}
                  </span>
                  <div className="flex flex-shrink-0 items-center gap-2">
                    <StatusBadge status={task.status} size="sm" />
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setPendingDeleteTask(task);
                      }}
                      aria-label={`Delete ${task.title}`}
                      className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-destructive"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        ) : (
          <p className="text-sm text-gray-500">No tasks yet.</p>
        )}
      </div>

      {/* Costs: hidden entirely without finance.view */}
      {can("finance.view") && (
        <div>
          <div className="mb-3 flex items-center justify-between">
            <h3 className="text-sm font-semibold uppercase tracking-wide text-gray-700">
              Costs
            </h3>
            {can("finance.manage") && (
              <Button
                size="sm"
                variant="outline"
                onClick={() => setAddCostOpen(true)}
                data-testid="add-cost-button"
              >
                <Plus className="h-3.5 w-3.5" />
                Add cost
              </Button>
            )}
          </div>
          <CostEntryList entries={costEntries} />
        </div>
      )}

      <AddCostDialog
        open={addCostOpen}
        onOpenChange={setAddCostOpen}
        tradeScopeId={scope.id}
      />

      <Dialog
        open={pendingDeleteTask !== null}
        onOpenChange={(open) => {
          if (!open) setPendingDeleteTask(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete this task?</DialogTitle>
            <DialogDescription>
              &ldquo;{pendingDeleteTask?.title}&rdquo; will be permanently removed. This
              cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setPendingDeleteTask(null)}
              disabled={deleteTaskMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={() =>
                pendingDeleteTask && deleteTaskMutation.mutate(pendingDeleteTask.id)
              }
              disabled={deleteTaskMutation.isPending}
            >
              {deleteTaskMutation.isPending ? "Deleting…" : "Delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
