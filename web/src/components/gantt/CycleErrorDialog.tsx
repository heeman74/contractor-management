"use client";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

interface CycleErrorDialogProps {
  open: boolean;
  onClose: () => void;
  cycleNames: string[];
  cycleIds: string[];
}

export function CycleErrorDialog({
  open,
  onClose,
  cycleNames,
}: CycleErrorDialogProps) {
  const cycleChain = cycleNames.join(" -> ");

  return (
    <Dialog open={open} onOpenChange={(isOpen) => { if (!isOpen) onClose(); }}>
      <DialogContent role="alertdialog" aria-describedby="cycle-error-desc">
        <DialogHeader>
          <DialogTitle>Dependency creates a loop</DialogTitle>
        </DialogHeader>
        <p id="cycle-error-desc" className="text-sm text-gray-600">
          This link creates a cycle: <span className="font-medium text-gray-900">{cycleChain}</span>.
          Remove one of these links to break the loop.
        </p>
        <DialogFooter>
          <Button onClick={onClose} className="bg-primary hover:bg-primary/90 text-white">
            Got it
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
