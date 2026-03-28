"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiPost } from "@/lib/api-client";
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
import type { UserCreateRequest, RoleAssignmentRequest } from "@/types/api";

const TRADE_TYPES = [
  "Plumbing",
  "Electrical",
  "Building",
  "Painting",
  "Carpentry",
  "Landscaping",
  "HVAC",
  "General",
] as const;

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
              <Select value={tradeType} onValueChange={(v) => setTradeType(v ?? "")}>
                <SelectTrigger id="contractor-trade" className="w-full">
                  <SelectValue placeholder="Select a trade..." />
                </SelectTrigger>
                <SelectContent>
                  {TRADE_TYPES.map((trade) => (
                    <SelectItem key={trade} value={trade.toLowerCase()}>
                      {trade}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
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
