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
import { GripVertical, Trash2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import type { TradeScope } from "../hooks/useIntakeChat";

// --- Sortable row ---

interface SortableRowProps {
  scope: TradeScope;
  index: number;
  onUpdate: (index: number, updates: Partial<TradeScope>) => void;
  onRemove: (index: number) => void;
}

function SortableRow({ scope, index, onUpdate, onRemove }: SortableRowProps) {
  const { attributes, listeners, setNodeRef, transform, transition } =
    useSortable({ id: `scope-${index}` });
  const [editing, setEditing] = useState(false);
  const [editValue, setEditValue] = useState(scope.trade_name);

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  const handleBlur = () => {
    setEditing(false);
    if (editValue.trim() !== scope.trade_name) {
      onUpdate(index, { trade_name: editValue.trim() });
    }
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="flex items-center gap-3 rounded-lg border bg-background px-3 py-2"
    >
      {/* Drag handle */}
      <button
        type="button"
        {...attributes}
        {...listeners}
        className="cursor-grab text-muted-foreground hover:text-foreground"
        aria-label="Drag to reorder"
      >
        <GripVertical className="h-4 w-4" />
      </button>

      {/* Color swatch */}
      <div
        className="h-5 w-5 flex-shrink-0 rounded-full border"
        style={{ backgroundColor: scope.trade_color }}
      />

      {/* Trade name — click to edit */}
      {editing ? (
        <input
          autoFocus
          value={editValue}
          onChange={(e) => setEditValue(e.target.value)}
          onBlur={handleBlur}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.currentTarget.blur();
            }
          }}
          className="flex-1 rounded border px-2 py-0.5 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
        />
      ) : (
        <span
          className="flex-1 cursor-pointer text-sm hover:underline"
          onClick={() => setEditing(true)}
          role="button"
          tabIndex={0}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") setEditing(true);
          }}
        >
          {scope.trade_name}
        </span>
      )}

      {/* Sort order */}
      <span className="w-5 text-center text-xs text-muted-foreground">
        {scope.sort_order + 1}
      </span>

      {/* Delete */}
      <button
        type="button"
        onClick={() => onRemove(index)}
        className="text-muted-foreground hover:text-destructive"
        aria-label={`Remove ${scope.trade_name}`}
      >
        <Trash2 className="h-4 w-4" />
      </button>
    </div>
  );
}

// --- Main card ---

interface TradeScopePreviewCardProps {
  tradeScopes: TradeScope[];
  onUpdate: (index: number, updates: Partial<TradeScope>) => void;
  onRemove: (index: number) => void;
  onReorder: (newOrder: TradeScope[]) => void;
  onCreateProject: () => void;
  isLoading?: boolean;
  isSaving?: boolean;
}

export function TradeScopePreviewCard({
  tradeScopes,
  onUpdate,
  onRemove,
  onReorder,
  onCreateProject,
  isLoading = false,
  isSaving = false,
}: TradeScopePreviewCardProps) {
  const sensors = useSensors(useSensor(PointerSensor));

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const oldIndex = tradeScopes.findIndex(
      (_, i) => `scope-${i}` === active.id
    );
    const newIndex = tradeScopes.findIndex(
      (_, i) => `scope-${i}` === over.id
    );

    if (oldIndex !== -1 && newIndex !== -1) {
      onReorder(arrayMove(tradeScopes, oldIndex, newIndex));
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Trade Scopes</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {isLoading ? (
          // Loading skeleton — 3 rows
          <>
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-10 w-full rounded-lg" />
            ))}
          </>
        ) : tradeScopes.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No trade scopes generated yet.
          </p>
        ) : (
          <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragEnd={handleDragEnd}
          >
            <SortableContext
              items={tradeScopes.map((_, i) => `scope-${i}`)}
              strategy={verticalListSortingStrategy}
            >
              <div className="flex flex-col gap-2">
                {tradeScopes.map((scope, index) => (
                  <SortableRow
                    key={`scope-${index}`}
                    scope={scope}
                    index={index}
                    onUpdate={onUpdate}
                    onRemove={onRemove}
                  />
                ))}
              </div>
            </SortableContext>
          </DndContext>
        )}

        {/* Create Project CTA */}
        <Button
          className="mt-2 w-full"
          disabled={tradeScopes.length === 0 || isSaving || isLoading}
          onClick={onCreateProject}
        >
          {isSaving ? "Creating..." : "Create Project"}
        </Button>
      </CardContent>
    </Card>
  );
}
