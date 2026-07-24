import type { DateOverride, WeeklyBlock } from "@/types/api";

export interface CustomBlock {
  startHour: string;
  endHour: string;
}

export const DEFAULT_CUSTOM_BLOCK: CustomBlock = {
  startHour: "09:00",
  endHour: "17:00",
};

const EARLIEST_HOUR = 6;
const LATEST_HOUR = 20;

/** Selectable working hours "06:00" … "20:00". */
export const HOUR_OPTIONS = Array.from(
  { length: LATEST_HOUR - EARLIEST_HOUR + 1 },
  (_, i) => `${String(i + EARLIEST_HOUR).padStart(2, "0")}:00`
);

/** Local-timezone ISO date (YYYY-MM-DD) — matches how override dates are keyed. */
export function toIsoDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function formatOverrideDate(date: Date): string {
  return date.toLocaleDateString(undefined, {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

/** Parses an override date string as local midnight (avoids UTC off-by-one). */
export function parseOverrideDate(overrideDate: string): Date {
  return new Date(`${overrideDate}T00:00:00`);
}

/**
 * Converts the API's weekly schedule (blocks per weekday) into the ScheduleGrid's
 * shape: a map of weekday -> list of selected hours within working bounds.
 */
export function weeklyScheduleToGrid(
  weeklySchedule: Record<string, WeeklyBlock[]> | undefined
): Record<number, number[]> {
  const grid: Record<number, number[]> = {};
  if (!weeklySchedule) return grid;

  for (const [dayStr, blocks] of Object.entries(weeklySchedule)) {
    const day = parseInt(dayStr);
    const hours: number[] = [];
    for (const block of blocks) {
      const startHour = parseInt(block.start_time.split(":")[0]);
      const endHour = parseInt(block.end_time.split(":")[0]);
      for (let h = startHour; h < endHour; h++) {
        if (h >= EARLIEST_HOUR && h <= LATEST_HOUR) hours.push(h);
      }
    }
    grid[day] = hours;
  }
  return grid;
}

/** The API returns one row per block; collapse to one entry per date. */
export function dedupeOverridesByDate(overrides: DateOverride[]): DateOverride[] {
  return Array.from(
    new Map(overrides.map((o) => [o.override_date, o])).values()
  );
}
