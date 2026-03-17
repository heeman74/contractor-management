"use client";

import {
  format,
  addDays,
  subDays,
  addWeeks,
  subWeeks,
  addMonths,
  subMonths,
  startOfWeek,
  endOfWeek,
} from "date-fns";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { CalendarView } from "@/types/schedule";

interface CalendarToolbarProps {
  date: Date;
  view: CalendarView;
  onNavigate: (date: Date) => void;
  onViewChange: (view: CalendarView) => void;
}

function getFormattedRange(date: Date, view: CalendarView): string {
  switch (view) {
    case "week": {
      const weekStart = startOfWeek(date);
      const weekEnd = endOfWeek(date);
      // Same month: "Mar 16 - 22, 2026"
      if (weekStart.getMonth() === weekEnd.getMonth()) {
        return `${format(weekStart, "MMM d")} - ${format(weekEnd, "d, yyyy")}`;
      }
      // Cross-month: "Mar 30 - Apr 5, 2026"
      return `${format(weekStart, "MMM d")} - ${format(weekEnd, "MMM d, yyyy")}`;
    }
    case "day":
      return format(date, "MMM d, yyyy");
    case "month":
      return format(date, "MMMM yyyy");
  }
}

function navigatePrev(date: Date, view: CalendarView): Date {
  switch (view) {
    case "week":
      return subWeeks(date, 1);
    case "day":
      return subDays(date, 1);
    case "month":
      return subMonths(date, 1);
  }
}

function navigateNext(date: Date, view: CalendarView): Date {
  switch (view) {
    case "week":
      return addWeeks(date, 1);
    case "day":
      return addDays(date, 1);
    case "month":
      return addMonths(date, 1);
  }
}

const VIEW_OPTIONS: { label: string; value: CalendarView }[] = [
  { label: "Week", value: "week" },
  { label: "Day", value: "day" },
  { label: "Month", value: "month" },
];

export function CalendarToolbar({
  date,
  view,
  onNavigate,
  onViewChange,
}: CalendarToolbarProps) {
  const formattedRange = getFormattedRange(date, view);

  return (
    <div className="flex items-center px-0 py-3 border-b border-gray-200">
      {/* Left group: Today + Prev/Next + Date range */}
      <div className="flex items-center gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() => onNavigate(new Date())}
        >
          Today
        </Button>

        <Button
          variant="ghost"
          size="icon"
          onClick={() => onNavigate(navigatePrev(date, view))}
          aria-label="Previous"
        >
          <ChevronLeft className="h-4 w-4" />
        </Button>

        <Button
          variant="ghost"
          size="icon"
          onClick={() => onNavigate(navigateNext(date, view))}
          aria-label="Next"
        >
          <ChevronRight className="h-4 w-4" />
        </Button>

        <span className="text-base font-semibold text-gray-900">
          {formattedRange}
        </span>
      </div>

      {/* Right group: View switcher */}
      <div className="flex items-center gap-2 ml-auto">
        {VIEW_OPTIONS.map((option) => (
          <Button
            key={option.value}
            variant={view === option.value ? "default" : "outline"}
            size="sm"
            onClick={() => onViewChange(option.value)}
          >
            {option.label}
          </Button>
        ))}
      </div>
    </div>
  );
}
