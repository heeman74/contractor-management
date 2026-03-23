"use client";

import { useState } from "react";
import {
  DndContext,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  arrayMove,
  SortableContext,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { GripVertical, Trash2, Plus } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import type { TaskPreview } from "../hooks/useInterviewChat";

// --- Sortable task card ---

interface SortableTaskCardProps {
  task: TaskPreview;
  index: number;
  onUpdate: (index: number, updates: Partial<TaskPreview>) => void;
  onRemove: (index: number) => void;
}

const PRIORITY_COLORS = {
  low: "secondary",
  medium: "outline",
  high: "destructive",
} as const;

function SortableTaskCard({
  task,
  index,
  onUpdate,
  onRemove,
}: SortableTaskCardProps) {
  const { attributes, listeners, setNodeRef, transform, transition } =
    useSortable({ id: `task-${index}` });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  return (
    <div ref={setNodeRef} style={style}>
      <Card className="border border-border">
        <CardContent className="flex flex-col gap-2 p-3">
          {/* Header row: drag handle + title + priority + delete */}
          <div className="flex items-start gap-2">
            <button
              type="button"
              {...attributes}
              {...listeners}
              className="mt-0.5 cursor-grab text-muted-foreground hover:text-foreground"
              aria-label="Drag to reorder"
            >
              <GripVertical className="h-4 w-4" />
            </button>

            <input
              className="flex-1 rounded border-0 bg-transparent text-sm font-medium focus:outline-none focus:ring-1 focus:ring-ring"
              value={task.title}
              onChange={(e) => onUpdate(index, { title: e.target.value })}
              placeholder="Task title"
            />

            {task.priority && (
              <Badge
                variant={PRIORITY_COLORS[task.priority] ?? "outline"}
                className="flex-shrink-0 text-xs"
              >
                {task.priority}
              </Badge>
            )}

            <button
              type="button"
              onClick={() => onRemove(index)}
              className="text-muted-foreground hover:text-destructive"
              aria-label={`Remove task ${task.title}`}
            >
              <Trash2 className="h-4 w-4" />
            </button>
          </div>

          {/* Description */}
          <textarea
            className="w-full resize-none rounded border-0 bg-transparent text-xs text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring"
            value={task.description ?? ""}
            onChange={(e) => onUpdate(index, { description: e.target.value })}
            placeholder="Description (optional)"
            rows={2}
          />

          {/* Estimated hours */}
          <div className="flex items-center gap-2">
            <span className="text-xs text-muted-foreground">Est. hours:</span>
            <input
              type="number"
              className="w-16 rounded border px-2 py-0.5 text-xs focus:outline-none focus:ring-1 focus:ring-ring"
              value={task.estimated_hours ?? ""}
              min={0}
              step={0.5}
              onChange={(e) =>
                onUpdate(index, {
                  estimated_hours: e.target.value
                    ? parseFloat(e.target.value)
                    : undefined,
                })
              }
              placeholder="—"
            />
          </div>

          {/* Materials */}
          <div>
            <span className="text-xs text-muted-foreground">Materials: </span>
            <input
              className="w-full rounded border-0 bg-transparent text-xs focus:outline-none focus:ring-1 focus:ring-ring"
              value={task.materials_needed ?? ""}
              onChange={(e) =>
                onUpdate(index, { materials_needed: e.target.value })
              }
              placeholder="Materials needed (optional)"
            />
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

// --- Main list ---

interface TaskPreviewListProps {
  tasks: TaskPreview[];
  onUpdate: (index: number, updates: Partial<TaskPreview>) => void;
  onRemove: (index: number) => void;
  onReorder: (newOrder: TaskPreview[]) => void;
  onAddTask: () => void;
  onAcceptPlan: () => void;
  onRestartInterview: () => void;
  isLoading?: boolean;
  isSaving?: boolean;
  tradeName?: string;
}

export function TaskPreviewList({
  tasks,
  onUpdate,
  onRemove,
  onReorder,
  onAddTask,
  onAcceptPlan,
  onRestartInterview,
  isLoading = false,
  isSaving = false,
  tradeName = "this trade",
}: TaskPreviewListProps) {
  const sensors = useSensors(useSensor(PointerSensor));
  const [restartDialogOpen, setRestartDialogOpen] = useState(false);

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const oldIndex = tasks.findIndex((_, i) => `task-${i}` === active.id);
    const newIndex = tasks.findIndex((_, i) => `task-${i}` === over.id);
    if (oldIndex !== -1 && newIndex !== -1) {
      onReorder(arrayMove(tasks, oldIndex, newIndex));
    }
  };

  const handleConfirmRestart = () => {
    setRestartDialogOpen(false);
    onRestartInterview();
  };

  return (
    <div className="flex flex-col gap-3">
      {/* Header */}
      <div className="flex items-center justify-between">
        <span className="text-sm font-semibold">
          Task Plan
          {tasks.length > 0 && (
            <span className="ml-1 text-muted-foreground font-normal">
              ({tasks.length} tasks)
            </span>
          )}
        </span>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={onAddTask}
          disabled={isSaving}
        >
          <Plus className="h-3 w-3" />
          Add Task
        </Button>
      </div>

      {/* Loading state */}
      {isLoading ? (
        <div className="flex flex-col gap-2">
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-24 w-full rounded-lg" />
          ))}
        </div>
      ) : tasks.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No tasks were generated. Try restarting the interview.
        </p>
      ) : (
        <DndContext
          sensors={sensors}
          collisionDetection={closestCenter}
          onDragEnd={handleDragEnd}
        >
          <SortableContext
            items={tasks.map((_, i) => `task-${i}`)}
            strategy={verticalListSortingStrategy}
          >
            <div className="flex flex-col gap-2">
              {tasks.map((task, index) => (
                <SortableTaskCard
                  key={`task-${index}`}
                  task={task}
                  index={index}
                  onUpdate={onUpdate}
                  onRemove={onRemove}
                />
              ))}
            </div>
          </SortableContext>
        </DndContext>
      )}

      {/* CTAs */}
      <div className="flex gap-2 pt-1">
        <Button
          className="flex-1"
          disabled={tasks.length === 0 || isSaving || isLoading}
          onClick={onAcceptPlan}
        >
          {isSaving ? "Saving..." : "Accept Plan"}
        </Button>
        <Button
          variant="outline"
          disabled={isSaving}
          onClick={() => setRestartDialogOpen(true)}
        >
          Restart Interview
        </Button>
      </div>

      {/* Re-interview confirmation dialog */}
      <Dialog open={restartDialogOpen} onOpenChange={setRestartDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Restart Interview?</DialogTitle>
            <DialogDescription>
              This will replace all {tasks.length} existing task
              {tasks.length !== 1 ? "s" : ""} for {tradeName}. This cannot be
              undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter className="gap-2">
            <Button
              variant="outline"
              onClick={() => setRestartDialogOpen(false)}
            >
              Keep Current Plan
            </Button>
            <Button variant="destructive" onClick={handleConfirmRestart}>
              Restart Interview
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
