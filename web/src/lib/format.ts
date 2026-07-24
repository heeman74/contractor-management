/**
 * Shared display formatters. Keep pure and framework-free so any component or
 * server helper can reuse them without pulling in React or fetch logic.
 */

const MINUTES_PER_HOUR = 60;
const HOURS_PER_DAY = 24;
const DAYS_PER_WEEK = 7;

/** "in_progress" -> "In Progress" */
export function formatStatus(status: string | undefined | null): string {
  if (!status) return "";
  return status.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

/** A short "time ago" label, falling back to a locale date for anything ≥ 7 days. */
export function formatRelativeTime(dateStr: string): string {
  try {
    const date = new Date(dateStr);
    const diffMs = Date.now() - date.getTime();
    const diffMin = Math.floor(diffMs / (60 * 1000));
    const diffHours = Math.floor(diffMin / MINUTES_PER_HOUR);
    const diffDays = Math.floor(diffHours / HOURS_PER_DAY);

    if (diffMin < 1) return "just now";
    if (diffMin < MINUTES_PER_HOUR) return `${diffMin}m ago`;
    if (diffHours < HOURS_PER_DAY) return `${diffHours}h ago`;
    if (diffDays < DAYS_PER_WEEK) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  } catch {
    return "";
  }
}

/** Minutes -> "2h 15m" (omits a zero hour or zero minute component). */
export function formatDurationMinutes(minutes: number): string {
  const hours = Math.floor(minutes / MINUTES_PER_HOUR);
  const mins = minutes % MINUTES_PER_HOUR;
  if (hours === 0) return `${mins}m`;
  if (mins === 0) return `${hours}h`;
  return `${hours}h ${mins}m`;
}

/** Locale date+time, returning the raw string if it cannot be parsed. */
export function formatDateTime(dateStr: string): string {
  try {
    return new Date(dateStr).toLocaleString();
  } catch {
    return dateStr;
  }
}

/** Money amount (number or numeric string from the API) as "$1,234.50". */
export function formatCurrency(value: number | string): string {
  return `$${Number(value).toFixed(2)}`;
}

/** Locale date, returning a fallback for null/undefined/unparseable input. */
export function formatDate(
  dateStr: string | null | undefined,
  fallback = "—"
): string {
  if (!dateStr) return fallback;
  const date = new Date(dateStr);
  return Number.isNaN(date.getTime()) ? fallback : date.toLocaleDateString();
}
