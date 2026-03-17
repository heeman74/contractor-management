"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { format } from "date-fns";
import { apiGet } from "@/lib/api-client";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetFooter,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { useCreateBookingMutation } from "../_hooks/use-create-booking";
import type { Job } from "@/types/api";

interface BookingCreatePanelProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  contractorId: string;
  contractorName: string;
  startTime: Date;
  endTime: Date;
}

export function BookingCreatePanel({
  open,
  onOpenChange,
  contractorId,
  contractorName,
  startTime,
  endTime,
}: BookingCreatePanelProps) {
  const [selectedJobId, setSelectedJobId] = useState("");
  const [notes, setNotes] = useState("");

  const createBooking = useCreateBookingMutation();

  const { data: availableJobs } = useQuery({
    queryKey: ["jobs", "bookable"],
    queryFn: () => apiGet<Job[]>("/api/v1/jobs?status=quote&limit=200"),
    select: (data) =>
      data.filter((j) => j.status === "quote" || j.status === "scheduled"),
    enabled: open,
  });

  const jobs = availableJobs ?? [];

  function handleBookJob() {
    if (!selectedJobId) return;
    createBooking.mutate(
      {
        contractor_id: contractorId,
        job_id: selectedJobId,
        start: startTime.toISOString(),
        end: endTime.toISOString(),
        notes: notes || undefined,
      },
      {
        onSuccess: () => {
          onOpenChange(false);
          setSelectedJobId("");
          setNotes("");
        },
      }
    );
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="w-96">
        <SheetHeader>
          <SheetTitle>Schedule a Job</SheetTitle>
        </SheetHeader>

        <div className="flex flex-col gap-4 px-4 pt-2">
          {/* Contractor (read-only) */}
          <div>
            <p className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">
              Contractor
            </p>
            <p className="text-sm font-medium text-gray-900">{contractorName}</p>
          </div>

          {/* Date & Time (read-only) */}
          <div>
            <p className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">
              Date &amp; Time
            </p>
            <p className="text-sm text-gray-900">
              {format(startTime, "MMM d, yyyy h:mm a")} &ndash;{" "}
              {format(endTime, "h:mm a")}
            </p>
          </div>

          <Separator />

          {/* Job selection */}
          <div>
            <label
              htmlFor="booking-job-select"
              className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1 block"
            >
              Job
            </label>
            {jobs.length === 0 ? (
              <select
                id="booking-job-select"
                disabled
                className="w-full rounded-md border border-gray-300 bg-gray-50 px-3 py-2 text-sm text-gray-400"
              >
                <option>No unscheduled jobs available. Create a job first.</option>
              </select>
            ) : (
              <select
                id="booking-job-select"
                value={selectedJobId}
                onChange={(e) => setSelectedJobId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-gray-900"
              >
                <option value="">Select a job to schedule...</option>
                {jobs.map((job) => (
                  <option key={job.id} value={job.id}>
                    {job.description.length > 50
                      ? `${job.description.slice(0, 50)}…`
                      : job.description}
                  </option>
                ))}
              </select>
            )}
          </div>

          {/* Inline error */}
          {createBooking.isError && (
            <p className="text-sm text-red-600 mt-2">
              {createBooking.error instanceof Error
                ? createBooking.error.message
                : "Failed to create booking"}
            </p>
          )}
        </div>

        <SheetFooter className="flex flex-row gap-2 justify-end">
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
          >
            Cancel
          </Button>
          <Button
            variant="default"
            onClick={handleBookJob}
            disabled={!selectedJobId || createBooking.isPending}
          >
            Book Job
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}
