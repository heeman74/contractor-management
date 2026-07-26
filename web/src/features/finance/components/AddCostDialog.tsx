"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useCostCategories, useAddCostEntry, useUploadReceipt } from "../hooks";

interface AddCostDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Exactly one of jobId / tradeScopeId should be provided — the anchor for the new entry. */
  jobId?: string;
  tradeScopeId?: string;
  onSuccess?: () => void;
}

function todayIso(): string {
  return new Date().toISOString().split("T")[0];
}

export function AddCostDialog({
  open,
  onOpenChange,
  jobId,
  tradeScopeId,
  onSuccess,
}: AddCostDialogProps) {
  const { data: categories } = useCostCategories();
  const addCostEntry = useAddCostEntry();
  const uploadReceipt = useUploadReceipt();

  const [amount, setAmount] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [incurredDate, setIncurredDate] = useState(todayIso());
  const [vendor, setVendor] = useState("");
  const [note, setNote] = useState("");
  const [receiptFile, setReceiptFile] = useState<File | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  const isSubmitting = addCostEntry.isPending || uploadReceipt.isPending;

  function resetForm() {
    setAmount("");
    setCategoryId("");
    setIncurredDate(todayIso());
    setVendor("");
    setNote("");
    setReceiptFile(null);
    setFormError(null);
  }

  function handleOpenChange(nextOpen: boolean) {
    if (!nextOpen) resetForm();
    onOpenChange(nextOpen);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setFormError(null);

    const numericAmount = Number(amount);
    if (!amount.trim() || Number.isNaN(numericAmount) || numericAmount <= 0) {
      setFormError("Enter an amount greater than 0.");
      return;
    }
    if (!categoryId) {
      setFormError("Select a category.");
      return;
    }
    if (!incurredDate) {
      setFormError("Select a date.");
      return;
    }

    try {
      const entry = await addCostEntry.mutateAsync({
        jobId,
        tradeScopeId,
        categoryId,
        amount,
        incurredDate,
        vendor: vendor.trim() || undefined,
        note: note.trim() || undefined,
      });

      if (receiptFile) {
        await uploadReceipt.mutateAsync({ costEntryId: entry.id, file: receiptFile });
      }

      toast.success("Cost entry added.");
      resetForm();
      onOpenChange(false);
      onSuccess?.();
    } catch {
      setFormError("Failed to add cost entry. Please try again.");
      toast.error("Failed to add cost entry.");
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Cost</DialogTitle>
            <DialogDescription>
              Record a materials, subcontractor, or other cost against this{" "}
              {jobId ? "job" : "trade scope"}.
            </DialogDescription>
          </DialogHeader>

          <div className="grid gap-4 py-4">
            {formError && (
              <div
                className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive"
                role="alert"
              >
                {formError}
              </div>
            )}

            <div className="grid gap-2">
              <Label htmlFor="cost-amount">
                Amount <span className="text-destructive">*</span>
              </Label>
              <Input
                id="cost-amount"
                type="number"
                step="0.01"
                placeholder="0.00"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                required
              />
            </div>

            <div className="grid gap-2">
              <Label htmlFor="cost-category">
                Category <span className="text-destructive">*</span>
              </Label>
              <Select value={categoryId} onValueChange={(v) => setCategoryId(v ?? "")}>
                <SelectTrigger id="cost-category" className="w-full">
                  <SelectValue placeholder="Select category..." />
                </SelectTrigger>
                <SelectContent>
                  {categories?.map((category) => (
                    <SelectItem key={category.id} value={category.id}>
                      {category.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="grid gap-2">
              <Label htmlFor="cost-date">
                Date <span className="text-destructive">*</span>
              </Label>
              <Input
                id="cost-date"
                type="date"
                value={incurredDate}
                onChange={(e) => setIncurredDate(e.target.value)}
                required
              />
            </div>

            <div className="grid gap-2">
              <Label htmlFor="cost-vendor">Vendor</Label>
              <Input
                id="cost-vendor"
                type="text"
                placeholder="Vendor name"
                value={vendor}
                onChange={(e) => setVendor(e.target.value)}
              />
            </div>

            <div className="grid gap-2">
              <Label htmlFor="cost-note">Note</Label>
              <Input
                id="cost-note"
                type="text"
                placeholder="Optional note"
                value={note}
                onChange={(e) => setNote(e.target.value)}
              />
            </div>

            <div className="grid gap-2">
              <Label htmlFor="cost-receipt">Receipt (optional)</Label>
              <input
                id="cost-receipt"
                type="file"
                accept="image/*,application/pdf"
                onChange={(e) => setReceiptFile(e.target.files?.[0] ?? null)}
                className="text-sm"
              />
            </div>
          </div>

          <DialogFooter>
            <Button type="submit" disabled={isSubmitting}>
              {isSubmitting ? "Adding..." : "Add Cost"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
