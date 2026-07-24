import { cn } from "@/lib/utils";

interface StatusBadgeProps {
  status: string;
  size?: "sm" | "md";
}

const colorMap: Record<string, string> = {
  // Green — completed/positive states
  active: "bg-green-100 text-green-800",
  paid: "bg-green-100 text-green-800",
  approved: "bg-green-100 text-green-800",
  complete: "bg-green-100 text-green-800",
  completed: "bg-green-100 text-green-800",
  // Yellow — in-progress states
  pending: "bg-yellow-100 text-yellow-800",
  in_progress: "bg-yellow-100 text-yellow-800",
  "in-progress": "bg-yellow-100 text-yellow-800",
  // Red — negative/overdue states
  overdue: "bg-red-100 text-red-800",
  declined: "bg-red-100 text-red-800",
  cancelled: "bg-red-100 text-red-800",
  canceled: "bg-red-100 text-red-800",
  // Blue — scheduled/sent states
  scheduled: "bg-blue-100 text-blue-800",
  sent: "bg-blue-100 text-blue-800",
  // Indigo — quote states
  quote: "bg-indigo-100 text-indigo-800",
  // Teal — invoiced states
  invoiced: "bg-teal-100 text-teal-800",
  // Gray — draft states
  draft: "bg-gray-100 text-gray-700",
  // Quote statuses (new)
  viewed: "bg-purple-100 text-purple-800",
  expired: "bg-orange-100 text-orange-800",
  revised: "bg-gray-100 text-gray-700",
  // Invoice statuses (new)
  unpaid: "bg-yellow-100 text-yellow-800",
  partially_paid: "bg-blue-100 text-blue-800",
  finalized: "bg-teal-100 text-teal-800",
  // Availability statuses (Phase 17)
  available: "bg-green-100 text-green-800",
  partially_booked: "bg-yellow-100 text-yellow-800",
  fully_booked: "bg-red-100 text-red-800",
  // Project statuses (Phase 19)
  planning: "bg-blue-100 text-blue-800",
  on_hold: "bg-yellow-100 text-yellow-800",
  archived: "bg-gray-100 text-gray-500",
  // Trade scope / task statuses (Phase 19)
  not_started: "bg-gray-100 text-gray-700",
  blocked: "bg-red-100 text-red-800",
  // Contract statuses (Phase 29)
  signed: "bg-green-100 text-green-800",
  voided: "bg-gray-100 text-gray-500",
};

export function StatusBadge({ status, size = "md" }: StatusBadgeProps) {
  // Defend against missing status — API data (e.g. heterogeneous status_history
  // entries) can omit it, and a hard crash here would take down the whole page.
  const safeStatus = status ?? "";
  const normalizedStatus = safeStatus.toLowerCase().replace(/ /g, "_");
  const colorClasses = colorMap[normalizedStatus] ?? "bg-gray-100 text-gray-700";
  const label = safeStatus.replace(/_/g, " ").replace(/-/g, " ") || "unknown";

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-sm border border-black/5 font-mono font-semibold uppercase tracking-wide tabular-nums",
        size === "sm" ? "px-1.5 py-0.5 text-[10px]" : "px-2 py-0.5 text-[11px]",
        colorClasses
      )}
    >
      {label}
    </span>
  );
}
