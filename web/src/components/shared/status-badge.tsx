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
};

export function StatusBadge({ status, size = "md" }: StatusBadgeProps) {
  const normalizedStatus = status.toLowerCase().replace(/ /g, "_");
  const colorClasses = colorMap[normalizedStatus] ?? "bg-gray-100 text-gray-700";

  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full font-medium",
        size === "sm" ? "px-2 py-0.5 text-xs" : "px-2.5 py-0.5 text-xs",
        colorClasses
      )}
    >
      {status.replace(/_/g, " ").replace(/-/g, " ")}
    </span>
  );
}
