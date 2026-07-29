"use client";

import { Button } from "@/components/ui/button";
import { TREND_WINDOWS, type TrendWindow } from "@/features/finance/types";

/** Pitfall 2 made visible: the window slices buckets, never the records inside them. */
export const TREND_WINDOW_NOTE =
  "Cumulative from project start — the window only changes how far back the chart shows.";

const TREND_WINDOW_LABELS: Record<TrendWindow, string> = {
  "3m": "Last 3m",
  "6m": "Last 6m",
  "12m": "Last 12m",
  all: "All time",
};

/** The shipped DateRangeFilter preset recipe, so every preset row on every
 *  dashboard reads as one control family. */
const ACTIVE_BUTTON_CLASS = "bg-brand/10 text-foreground border-brand font-semibold";

interface TrendWindowFilterProps {
  window: TrendWindow;
  onWindowChange: (window: TrendWindow) => void;
}

/**
 * Lives inside the trend card, never at page level: the tiles and the budget bars
 * beside it are lifetime figures, and a page-level control would imply otherwise.
 */
export function TrendWindowFilter({ window, onWindowChange }: TrendWindowFilterProps) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {TREND_WINDOWS.map((value) => (
        <Button
          key={value}
          variant="outline"
          size="sm"
          data-testid={`trend-window-${value}`}
          aria-pressed={value === window}
          className={value === window ? ACTIVE_BUTTON_CLASS : ""}
          onClick={() => onWindowChange(value)}
        >
          {TREND_WINDOW_LABELS[value]}
        </Button>
      ))}
    </div>
  );
}
