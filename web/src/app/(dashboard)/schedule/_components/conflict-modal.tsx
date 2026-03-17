"use client";

import { AlertTriangle } from "lucide-react";
import { format } from "date-fns";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import type { ConflictDetail } from "@/types/schedule";

interface ConflictModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  conflicts: ConflictDetail[];
  onConfirm: () => void;
  onCancel: () => void;
}

/**
 * Conflict warning dialog shown before a drag-and-drop reschedule is confirmed.
 *
 * Displays details of any conflicting bookings so the admin can decide whether
 * to override the conflict ("Confirm Anyway") or roll back the move ("Cancel").
 * "Cancel" returns the booking to its original position — no mutation is fired.
 */
export function ConflictModal({
  open,
  onOpenChange,
  conflicts,
  onConfirm,
  onCancel,
}: ConflictModalProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showCloseButton={false} className="max-w-md" aria-describedby="conflict-description">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-lg font-semibold">
            <AlertTriangle className="h-5 w-5 text-yellow-500 shrink-0" />
            Scheduling Conflict Detected
          </DialogTitle>
        </DialogHeader>

        <DialogDescription id="conflict-description">
          This time slot conflicts with an existing booking:
        </DialogDescription>

        <div className="max-h-48 overflow-y-auto space-y-2">
          {conflicts.map((conflict) => (
            <div
              key={conflict.booking_id}
              className="rounded-md bg-gray-50 p-3 text-sm space-y-1"
            >
              <div>
                <span className="font-medium">Job:</span>{" "}
                {conflict.job_id.slice(0, 8)}
              </div>
              <div>
                <span className="font-medium">Contractor:</span>{" "}
                {conflict.contractor_name ?? "Unknown"}
              </div>
              <div>
                <span className="font-medium">Time:</span>{" "}
                {format(new Date(conflict.time_range_start), "h:mm a")} -{" "}
                {format(new Date(conflict.time_range_end), "h:mm a")}
              </div>
            </div>
          ))}
        </div>

        <Separator />

        <DialogFooter>
          <Button variant="outline" onClick={onCancel}>
            Cancel
          </Button>
          <Button variant="default" onClick={onConfirm}>
            Confirm Anyway
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
