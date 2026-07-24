import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";

interface DeclineRequestDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  reason: string;
  onReasonChange: (reason: string) => void;
  onConfirm: () => void;
  isSubmitting: boolean;
}

export function DeclineRequestDialog({
  open,
  onOpenChange,
  reason,
  onReasonChange,
  onConfirm,
  isSubmitting,
}: DeclineRequestDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showCloseButton={false}>
        <DialogHeader>
          <DialogTitle>Decline this request?</DialogTitle>
          <DialogDescription>
            The client will be notified their request was declined. Please
            provide a reason.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
            Decline reason (required)
          </label>
          <Textarea
            value={reason}
            onChange={(e) => onReasonChange(e.target.value)}
            placeholder="Enter reason..."
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Keep Request
          </Button>
          <Button
            variant="destructive"
            disabled={!reason.trim() || isSubmitting}
            onClick={onConfirm}
          >
            Decline Request
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
