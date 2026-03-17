"use client";

import Link from "next/link";
import { format } from "date-fns";
import { ExternalLink } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetFooter,
} from "@/components/ui/sheet";
import { Separator } from "@/components/ui/separator";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { StatusBadge } from "@/components/shared/status-badge";
import type { CalendarBooking } from "@/types/schedule";

interface BookingPanelProps {
  booking: CalendarBooking | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  contractorName?: string;
}

function formatDuration(start: Date, end: Date): string {
  const diffMs = end.getTime() - start.getTime();
  const totalMinutes = Math.round(diffMs / 60000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours === 0) return `${minutes}m`;
  if (minutes === 0) return `${hours}h`;
  return `${hours}h ${minutes}m`;
}

export function BookingPanel({
  booking,
  open,
  onOpenChange,
  contractorName,
}: BookingPanelProps) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="w-96">
        {booking && (
          <>
            <SheetHeader>
              <div className="flex items-start justify-between gap-2 pr-8">
                <SheetTitle className="text-lg font-semibold leading-tight">
                  {booking.title}
                </SheetTitle>
                <StatusBadge status={booking.status} size="sm" />
              </div>
            </SheetHeader>

            <Separator />

            {/* Detail grid */}
            <div className="grid grid-cols-2 gap-y-4 text-sm px-4 py-2">
              <span className="text-gray-500 font-medium">Client</span>
              <span className="text-gray-900">
                {booking.clientName || "—"}
              </span>

              <span className="text-gray-500 font-medium">Time</span>
              <span className="text-gray-900">
                {format(booking.start, "h:mm a")} –{" "}
                {format(booking.end, "h:mm a")}
              </span>

              <span className="text-gray-500 font-medium">Duration</span>
              <span className="text-gray-900">
                {formatDuration(booking.start, booking.end)}
              </span>

              {contractorName && (
                <>
                  <span className="text-gray-500 font-medium">Contractor</span>
                  <span className="text-gray-900">{contractorName}</span>
                </>
              )}

              <span className="text-gray-500 font-medium">Address</span>
              <span className="text-gray-900">
                {booking.address ?? "No address"}
              </span>

              {booking.notes && (
                <>
                  <span className="text-gray-500 font-medium">Notes</span>
                  <span className="text-gray-900">{booking.notes}</span>
                </>
              )}
            </div>

            <Separator />

            <SheetFooter>
              <Link
                href={`/jobs/${booking.jobId}`}
                className={cn(buttonVariants({ variant: "outline", size: "sm" }), "inline-flex items-center gap-1.5")}
              >
                <ExternalLink className="h-4 w-4" />
                View Full Job
              </Link>
            </SheetFooter>
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}
