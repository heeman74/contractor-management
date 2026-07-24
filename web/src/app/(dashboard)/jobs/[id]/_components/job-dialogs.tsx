import { useState } from "react";
import type { JobStatus } from "@/types/api";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { formatStatus } from "@/lib/format";

const MAX_CANCEL_REASON_LENGTH = 500;

interface RevertJobDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  revertStatus: JobStatus | undefined;
  isTransitioning: boolean;
  onConfirm: () => void;
}

export function RevertJobDialog({
  open,
  onOpenChange,
  revertStatus,
  isTransitioning,
  onConfirm,
}: RevertJobDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showCloseButton>
        <DialogHeader>
          <DialogTitle>Revert job status?</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-gray-600">
          This will move the job back to{" "}
          <strong>{formatStatus(revertStatus)}</strong>. Are you sure?
        </p>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={onConfirm} disabled={isTransitioning}>
            Revert Status
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

interface CancelJobDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  isTransitioning: boolean;
  onConfirm: (reason: string) => void;
}

export function CancelJobDialog({
  open,
  onOpenChange,
  isTransitioning,
  onConfirm,
}: CancelJobDialogProps) {
  const [reason, setReason] = useState("");

  function handleOpenChange(next: boolean) {
    if (!next) setReason("");
    onOpenChange(next);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent showCloseButton>
        <DialogHeader>
          <DialogTitle>Cancel this job?</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-gray-600">
          This action cannot be undone. The job will be marked Cancelled and a
          note will be saved. Please provide a reason.
        </p>
        <div className="space-y-1">
          <label className="text-xs font-semibold text-gray-700">
            Cancellation reason (required)
          </label>
          <Textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Enter reason..."
            className="resize-none"
            maxLength={MAX_CANCEL_REASON_LENGTH}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => handleOpenChange(false)}>
            Keep Job
          </Button>
          <Button
            variant="destructive"
            disabled={!reason.trim() || isTransitioning}
            onClick={() => onConfirm(reason)}
          >
            Cancel Job
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
