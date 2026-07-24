import { useEffect } from "react";
import {
  addDays,
  subDays,
  addWeeks,
  subWeeks,
  addMonths,
  subMonths,
} from "date-fns";
import type { CalendarView } from "@/types/schedule";

interface KeyboardNavOptions {
  date: Date;
  view: CalendarView;
  navigate: (date: Date, view?: CalendarView) => void;
  /** When any panel/modal is open, only Escape is handled (to close it). */
  isOverlayOpen: boolean;
  onEscape: () => void;
}

function isTypingTarget(target: EventTarget | null): boolean {
  const el = target as HTMLElement | null;
  return (
    el?.tagName === "INPUT" ||
    el?.tagName === "TEXTAREA" ||
    Boolean(el?.isContentEditable)
  );
}

function stepBackward(date: Date, view: CalendarView): Date {
  if (view === "day") return subDays(date, 1);
  if (view === "month") return subMonths(date, 1);
  return subWeeks(date, 1);
}

function stepForward(date: Date, view: CalendarView): Date {
  if (view === "day") return addDays(date, 1);
  if (view === "month") return addMonths(date, 1);
  return addWeeks(date, 1);
}

/** DST-safe arrow/`t` keyboard navigation for the schedule calendar. */
export function useScheduleKeyboardNav({
  date,
  view,
  navigate,
  isOverlayOpen,
  onEscape,
}: KeyboardNavOptions) {
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (isTypingTarget(e.target)) return;

      if (e.key === "Escape") {
        onEscape();
        return;
      }

      // Suppress navigation while a panel or modal is open.
      if (isOverlayOpen) return;

      switch (e.key) {
        case "ArrowLeft":
          e.preventDefault();
          navigate(stepBackward(date, view));
          break;
        case "ArrowRight":
          e.preventDefault();
          navigate(stepForward(date, view));
          break;
        case "t":
        case "T":
          navigate(new Date());
          break;
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [date, view, navigate, isOverlayOpen, onEscape]);
}
