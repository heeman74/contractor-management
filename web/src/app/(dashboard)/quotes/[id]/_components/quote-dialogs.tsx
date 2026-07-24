import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";

interface SendQuoteDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  clientName: string;
  isSending: boolean;
  onConfirm: () => void;
}

export function SendQuoteDialog({
  open,
  onOpenChange,
  clientName,
  isSending,
  onConfirm,
}: SendQuoteDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showCloseButton>
        <DialogHeader>
          <DialogTitle>Send quote to {clientName}?</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-gray-600">
          They will receive a notification and can approve or decline this quote.
        </p>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={isSending}
          >
            Cancel
          </Button>
          <Button onClick={onConfirm} disabled={isSending}>
            Send Quote
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

interface ExtendExpiryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  isExtending: boolean;
  onConfirm: (newDate: string) => void;
}

export function ExtendExpiryDialog({
  open,
  onOpenChange,
  isExtending,
  onConfirm,
}: ExtendExpiryDialogProps) {
  const [newDate, setNewDate] = useState("");
  const todayIso = new Date().toISOString().split("T")[0];

  function handleOpenChange(next: boolean) {
    if (!next) setNewDate("");
    onOpenChange(next);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent showCloseButton>
        <DialogHeader>
          <DialogTitle>Extend Expiry Date</DialogTitle>
        </DialogHeader>
        <div className="space-y-2">
          <label className="text-xs font-semibold text-gray-700">
            New expiry date
          </label>
          <input
            type="date"
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            value={newDate}
            onChange={(e) => setNewDate(e.target.value)}
            min={todayIso}
          />
        </div>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => handleOpenChange(false)}
            disabled={isExtending}
          >
            Cancel
          </Button>
          <Button
            onClick={() => newDate && onConfirm(newDate)}
            disabled={!newDate || isExtending}
          >
            Extend Expiry
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
