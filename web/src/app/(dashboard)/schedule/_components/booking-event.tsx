"use client";

import { StatusBadge } from "@/components/shared/status-badge";
import type { CalendarBooking } from "@/types/schedule";
import { format } from "date-fns";

const statusBorderMap: Record<string, string> = {
  scheduled: "border-l-blue-400",
  in_progress: "border-l-yellow-400",
  complete: "border-l-green-400",
  quote: "border-l-indigo-400",
  invoiced: "border-l-teal-400",
  overdue: "border-l-red-400",
  cancelled: "border-l-red-400",
};

const statusBgMap: Record<string, string> = {
  scheduled: "bg-blue-100",
  in_progress: "bg-yellow-100",
  complete: "bg-green-100",
  quote: "bg-indigo-100",
  invoiced: "bg-teal-100",
  overdue: "bg-red-100",
  cancelled: "bg-red-100",
};

interface BookingEventProps {
  event: CalendarBooking;
}

export function BookingEvent({ event }: BookingEventProps) {
  const borderColor = statusBorderMap[event.status] ?? "border-l-gray-400";
  const bgColor = statusBgMap[event.status] ?? "bg-gray-100";

  const timeLabel = `${format(event.start, "h:mm a")} - ${format(event.end, "h:mm a")}`;
  const ariaLabel = `${event.title}${event.clientName ? ` - ${event.clientName}` : ""} - ${timeLabel}`;

  return (
    <div
      role="button"
      aria-label={ariaLabel}
      className={`relative rounded-md p-1.5 overflow-visible border-l-4 h-full cursor-pointer ${borderColor} ${bgColor}`}
    >
      {/* Status badge top-right */}
      <div className="absolute top-0.5 right-0.5">
        <StatusBadge status={event.status} size="sm" />
      </div>

      {/* Job title */}
      <p className="text-base font-semibold overflow-visible whitespace-nowrap pr-16">
        {event.title}
      </p>

      {/* Client name */}
      {event.clientName && (
        <p className="text-sm text-gray-500 overflow-visible whitespace-nowrap">
          {event.clientName}
        </p>
      )}

      {/* Multi-day badge */}
      {event.dayIndex !== undefined && (
        <div className="text-xs font-medium bg-white/80 rounded px-1 absolute bottom-1 right-1">
          Day {event.dayIndex}
        </div>
      )}
    </div>
  );
}
