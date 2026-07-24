"use client";

import { useState, useCallback } from "react";
import { useMutation } from "@tanstack/react-query";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { apiPut } from "@/lib/api-client";
import type { TimeBlock } from "@/types/api";

interface ScheduleGridProps {
  contractorId: string;
  initialSchedule: Record<number, number[]>; // day (0-6) -> array of hour indices (6-20)
  onDaySaved?: (day: number) => void;
}

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] as const;
const HOURS = Array.from({ length: 15 }, (_, i) => i + 6); // 6am to 8pm (6,7,...,20)

function hoursToBlocks(hours: number[]): TimeBlock[] {
  if (hours.length === 0) return [];
  const sorted = [...new Set(hours)].sort((a, b) => a - b);
  const blocks: TimeBlock[] = [];
  let start = sorted[0];
  let prev = sorted[0];
  for (let i = 1; i <= sorted.length; i++) {
    if (i === sorted.length || sorted[i] !== prev + 1) {
      blocks.push({
        start_time: `${String(start).padStart(2, "0")}:00`,
        end_time: `${String(prev + 1).padStart(2, "0")}:00`,
      });
      if (i < sorted.length) start = sorted[i];
    }
    if (i < sorted.length) prev = sorted[i];
  }
  return blocks;
}

export function ScheduleGrid({
  contractorId,
  initialSchedule,
  onDaySaved,
}: ScheduleGridProps) {
  const [schedule, setSchedule] = useState<Record<number, Set<number>>>(() => {
    const result: Record<number, Set<number>> = {};
    for (let d = 0; d < 7; d++) {
      result[d] = new Set(initialSchedule[d] ?? []);
    }
    return result;
  });
  const [isDragging, setIsDragging] = useState(false);
  const [paintValue, setPaintValue] = useState(true); // true = fill, false = clear
  const [changedDays, setChangedDays] = useState<Set<number>>(new Set());

  const saveMutation = useMutation({
    mutationFn: async ({ day, blocks }: { day: number; blocks: TimeBlock[] }) => {
      return apiPut(
        `/api/v1/scheduling/schedules/${contractorId}/weekly/${day}`,
        { blocks }
      );
    },
    onSuccess: (_, { day }) => {
      toast.success(`Schedule saved for ${DAYS[day]}.`);
      onDaySaved?.(day);
    },
    onError: (_, { day }) => {
      toast.error(`Failed to save schedule for ${DAYS[day]}. Please try again.`, {
        duration: Infinity,
      });
    },
  });

  const saveDaySchedule = useCallback(
    (day: number) => {
      const blocks = hoursToBlocks(Array.from(schedule[day]));
      saveMutation.mutate({ day, blocks });
    },
    [schedule, saveMutation]
  );

  function toggleCell(day: number, hour: number, fill: boolean) {
    setSchedule((prev) => {
      const newDay = new Set(prev[day]);
      if (fill) newDay.add(hour);
      else newDay.delete(hour);
      return { ...prev, [day]: newDay };
    });
    setChangedDays((prev) => new Set(prev).add(day));
  }

  function handleCellPointerDown(day: number, hour: number, e: React.PointerEvent) {
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    setIsDragging(true);
    const currentlyFilled = schedule[day].has(hour);
    setPaintValue(!currentlyFilled);
    toggleCell(day, hour, !currentlyFilled);
  }

  function handleCellPointerEnter(day: number, hour: number) {
    if (!isDragging) return;
    toggleCell(day, hour, paintValue);
  }

  function handlePointerUp() {
    if (!isDragging) return;
    setIsDragging(false);
    // Save all changed days
    changedDays.forEach((day) => saveDaySchedule(day));
    setChangedDays(new Set());
  }

  return (
    <div>
      <div
        className="select-none overflow-x-auto"
        onPointerUp={handlePointerUp}
      >
        {/* Header row: day labels */}
        <div className="grid grid-cols-[60px_repeat(7,1fr)] gap-px min-w-[480px]">
          <div /> {/* Empty corner cell */}
          {DAYS.map((day, i) => (
            <div
              key={i}
              className="text-center text-xs font-medium py-2 text-muted-foreground"
            >
              {day}
            </div>
          ))}
        </div>

        {/* Hour rows */}
        <div className="min-w-[480px]">
          {HOURS.map((hour) => (
            <div
              key={hour}
              className="grid grid-cols-[60px_repeat(7,1fr)] gap-px"
            >
              <div className="text-xs text-muted-foreground text-right pr-2 py-1 leading-7">
                {`${hour}:00`}
              </div>
              {DAYS.map((_, day) => {
                const filled = schedule[day]?.has(hour);
                return (
                  <div
                    key={`${day}-${hour}`}
                    className={cn(
                      "h-7 w-full border cursor-pointer transition-colors",
                      filled
                        ? "bg-brand hover:bg-primary border-brand"
                        : "bg-gray-100 hover:bg-secondary border-gray-200",
                      isDragging && "transition-none"
                    )}
                    onPointerDown={(e) => handleCellPointerDown(day, hour, e)}
                    onPointerEnter={() => handleCellPointerEnter(day, hour)}
                  />
                );
              })}
            </div>
          ))}
        </div>
      </div>
      <p className="text-sm text-muted-foreground mt-2">
        Click and drag to mark working hours. Changes save automatically per day.
      </p>
    </div>
  );
}
