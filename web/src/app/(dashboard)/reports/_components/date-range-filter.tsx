"use client";

import { useState } from "react";
import { subDays, startOfYear, format } from "date-fns";
import type { DateRange } from "react-day-picker";
import { CalendarIcon } from "lucide-react";
import { Calendar } from "@/components/ui/calendar";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Button } from "@/components/ui/button";

interface DateRangeFilterProps {
  dateRange: { from: Date; to: Date };
  onDateRangeChange: (range: { from: Date; to: Date }) => void;
}

type Preset = "7d" | "30d" | "90d" | "ytd";

function presetToRange(preset: Preset): { from: Date; to: Date } {
  switch (preset) {
    case "7d":
      return { from: subDays(new Date(), 7), to: new Date() };
    case "30d":
      return { from: subDays(new Date(), 30), to: new Date() };
    case "90d":
      return { from: subDays(new Date(), 90), to: new Date() };
    case "ytd":
      return { from: startOfYear(new Date()), to: new Date() };
  }
}

const PRESET_LABELS: Record<Preset, string> = {
  "7d": "Last 7d",
  "30d": "Last 30d",
  "90d": "Last 90d",
  ytd: "YTD",
};

export function DateRangeFilter({
  dateRange,
  onDateRangeChange,
}: DateRangeFilterProps) {
  const [activePreset, setActivePreset] = useState<Preset | "custom">("30d");
  const [popoverOpen, setPopoverOpen] = useState(false);

  function handlePresetClick(preset: Preset) {
    onDateRangeChange(presetToRange(preset));
    setActivePreset(preset);
  }

  function handleCalendarSelect(range: DateRange | undefined) {
    if (range?.from && range?.to) {
      onDateRangeChange({ from: range.from, to: range.to });
      setActivePreset("custom");
      setPopoverOpen(false);
    }
  }

  const customLabel =
    activePreset === "custom"
      ? `${format(dateRange.from, "MMM d")} \u2013 ${format(dateRange.to, "MMM d, yyyy")}`
      : "Custom range";

  return (
    <div className="flex flex-wrap items-center gap-2">
      {(["7d", "30d", "90d", "ytd"] as Preset[]).map((preset) => (
        <Button
          key={preset}
          variant="outline"
          size="sm"
          aria-pressed={activePreset === preset}
          className={
            activePreset === preset
              ? "bg-indigo-50 text-indigo-600 border-indigo-200"
              : ""
          }
          onClick={() => handlePresetClick(preset)}
        >
          {PRESET_LABELS[preset]}
        </Button>
      ))}
      <Popover open={popoverOpen} onOpenChange={setPopoverOpen}>
        <PopoverTrigger
          className={[
            "inline-flex shrink-0 items-center justify-center rounded-lg border text-sm font-medium h-7 gap-1 px-2.5 text-[0.8rem] transition-all",
            activePreset === "custom"
              ? "bg-indigo-50 text-indigo-600 border-indigo-200"
              : "border-border bg-background hover:bg-muted hover:text-foreground",
          ].join(" ")}
          aria-pressed={activePreset === "custom"}
        >
          <CalendarIcon className="h-3.5 w-3.5" />
          {customLabel}
        </PopoverTrigger>
        <PopoverContent className="w-auto p-0" align="start">
          <Calendar
            mode="range"
            selected={{ from: dateRange.from, to: dateRange.to }}
            onSelect={handleCalendarSelect}
            numberOfMonths={2}
          />
        </PopoverContent>
      </Popover>
    </div>
  );
}
