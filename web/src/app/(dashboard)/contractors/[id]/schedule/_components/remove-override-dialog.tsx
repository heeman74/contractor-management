import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { formatOverrideDate } from "../_lib/schedule-overrides";

interface RemoveOverrideDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  selectedDate: Date | undefined;
  onConfirm: () => void;
}

export function RemoveOverrideDialog({
  open,
  onOpenChange,
  selectedDate,
  onConfirm,
}: RemoveOverrideDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Remove override?</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-muted-foreground">
          This will delete the date override for{" "}
          {selectedDate ? formatOverrideDate(selectedDate) : "this date"}. The
          contractor&apos;s regular weekly schedule will apply.
        </p>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button variant="destructive" onClick={onConfirm}>
            Remove
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
