"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiPost } from "@/lib/api-client";
import { useTradeCatalog } from "@/lib/api/projects";
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
} from "@/components/ui/select";
import type { UserCreateRequest, RoleAssignmentRequest } from "@/types/api";

interface CreatedUser {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  phone: string | null;
}

interface CreateContractorDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CreateContractorDialog({ open, onOpenChange }: CreateContractorDialogProps) {
  const [email, setEmail] = useState("");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [phone, setPhone] = useState("");
  const [tradeType, setTradeType] = useState<string>("");
  const [formError, setFormError] = useState<string | null>(null);

  const queryClient = useQueryClient();
  // Trade options come from the shared trade catalog (same list managed in
  // Add Trade Scope), so a contractor's specialty always matches a real trade.
  const { data: tradeCatalog } = useTradeCatalog();
  // Array.isArray, not `?? []`: a non-list payload (an error body, an unmocked
  // route) is neither null nor undefined, so `??` passes it straight through to
  // .map and the whole dialog dies on "map is not a function" — taking the
  // email and name fields down with a fault that belongs to the trade picker.
  const trades = Array.isArray(tradeCatalog) ? tradeCatalog : [];
  // Distinguish "loaded and genuinely empty" from "still loading": only the
  // former earns the go-add-some-trades message.
  const catalogIsEmpty = Array.isArray(tradeCatalog) && trades.length === 0;
  // Derive the trigger label from our own data rather than the Select's cached
  // item text (which can fall back to the raw id).
  const selectedTrade = trades.find((trade) => trade.id === tradeType);

  const resetForm = () => {
    setEmail("");
    setFirstName("");
    setLastName("");
    setPhone("");
    setTradeType("");
    setFormError(null);
  };

  const mutation = useMutation({
    mutationFn: async () => {
      // Step 1: Create the user
      const body: UserCreateRequest = {
        email,
        first_name: firstName,
        last_name: lastName,
      };
      if (phone.trim()) {
        body.phone = phone.trim();
      }
      const user = await apiPost<CreatedUser>("/api/v1/users/", body);

      // Step 2: Assign contractor role
      const roleBody: RoleAssignmentRequest = {
        user_id: user.id,
        role: "contractor",
      };
      await apiPost(`/api/v1/users/${user.id}/roles`, roleBody);

      // Step 3: Link the chosen trade specialty (a shared catalog entry), if any
      if (tradeType) {
        await apiPost(`/api/v1/contractors/${user.id}/specialties`, {
          trade_catalog_id: tradeType,
        });
      }

      return user;
    },
    onSuccess: () => {
      toast.success("Contractor added");
      queryClient.invalidateQueries({ queryKey: ["users"] });
      onOpenChange(false);
      resetForm();
    },
    onError: (error: Error) => {
      const message =
        "detail" in error
          ? (error as { detail: string }).detail
          : error.message;
      setFormError(message || "Failed to create contractor");
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);

    // Client-side validation
    if (!email.trim()) {
      setFormError("Email is required");
      return;
    }
    if (!firstName.trim()) {
      setFormError("First name is required");
      return;
    }
    if (!lastName.trim()) {
      setFormError("Last name is required");
      return;
    }

    mutation.mutate();
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Contractor</DialogTitle>
            <DialogDescription>
              Create a new contractor account. They will receive an email to set
              their password.
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
              <Label htmlFor="contractor-email">
                Email <span className="text-destructive">*</span>
              </Label>
              <Input
                id="contractor-email"
                type="email"
                placeholder="contractor@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-2">
                <Label htmlFor="contractor-first-name">
                  First Name <span className="text-destructive">*</span>
                </Label>
                <Input
                  id="contractor-first-name"
                  type="text"
                  placeholder="John"
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  required
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="contractor-last-name">
                  Last Name <span className="text-destructive">*</span>
                </Label>
                <Input
                  id="contractor-last-name"
                  type="text"
                  placeholder="Doe"
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                  required
                />
              </div>
            </div>

            <div className="grid gap-2">
              <Label htmlFor="contractor-phone">Phone</Label>
              <Input
                id="contractor-phone"
                type="tel"
                placeholder="+1 (555) 123-4567"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
              />
            </div>

            <div className="grid gap-2">
              <Label htmlFor="contractor-trade">Trade Type</Label>
              {catalogIsEmpty ? (
                <p className="text-sm text-muted-foreground">
                  No trades yet. Add trades from a project&apos;s Add Trade Scope panel.
                </p>
              ) : (
                <Select value={tradeType} onValueChange={(v) => setTradeType(v ?? "")}>
                  <SelectTrigger id="contractor-trade" className="w-full">
                    {selectedTrade ? (
                      <span>{selectedTrade.name}</span>
                    ) : (
                      <span className="text-muted-foreground">Select a trade...</span>
                    )}
                  </SelectTrigger>
                  <SelectContent>
                    {trades.map((trade) => (
                      <SelectItem key={trade.id} value={trade.id}>
                        {trade.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
          </div>

          <DialogFooter>
            <Button
              type="submit"
              disabled={mutation.isPending}
            >
              {mutation.isPending ? "Creating..." : "Create Contractor"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
