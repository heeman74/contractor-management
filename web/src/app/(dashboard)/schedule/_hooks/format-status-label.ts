/** Format snake_case status values for display (e.g. "in_progress" -> "In Progress") */
export function formatStatusLabel(status: string): string {
  return status
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}
