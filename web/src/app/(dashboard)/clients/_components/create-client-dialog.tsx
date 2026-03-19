"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Plus } from "lucide-react";
import { apiPost } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import type {
  UserCreateRequest,
  ClientProfileCreateRequest,
  RoleAssignmentRequest,
} from "@/types/api";

interface CreateClientFormData {
  email: string;
  first_name: string;
  last_name: string;
  phone: string;
  billing_address: string;
  tags: string;
  admin_notes: string;
}

const INITIAL_FORM: CreateClientFormData = {
  email: "",
  first_name: "",
  last_name: "",
  phone: "",
  billing_address: "",
  tags: "",
  admin_notes: "",
};

interface CreateClientDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CreateClientDialog({ open, onOpenChange }: CreateClientDialogProps) {
  const [form, setForm] = useState<CreateClientFormData>(INITIAL_FORM);
  const [errors, setErrors] = useState<Partial<Record<keyof CreateClientFormData, string>>>({});
  const queryClient = useQueryClient();

  function validate(): boolean {
    const next: typeof errors = {};
    if (!form.email.trim()) {
      next.email = "Email is required";
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())) {
      next.email = "Invalid email address";
    }
    if (!form.first_name.trim()) next.first_name = "First name is required";
    if (!form.last_name.trim()) next.last_name = "Last name is required";
    setErrors(next);
    return Object.keys(next).length === 0;
  }

  const mutation = useMutation({
    mutationFn: async () => {
      // Step 1: Create the user
      const userPayload: UserCreateRequest = {
        email: form.email.trim(),
        first_name: form.first_name.trim(),
        last_name: form.last_name.trim(),
      };
      if (form.phone.trim()) userPayload.phone = form.phone.trim();

      const user = await apiPost<{ id: string }>("/api/v1/users/", userPayload);

      // Step 2: Create the client profile
      const profilePayload: ClientProfileCreateRequest = {
        user_id: user.id,
      };
      if (form.billing_address.trim()) profilePayload.billing_address = form.billing_address.trim();
      if (form.tags.trim()) {
        profilePayload.tags = form.tags
          .split(",")
          .map((t) => t.trim())
          .filter(Boolean);
      }
      if (form.admin_notes.trim()) profilePayload.admin_notes = form.admin_notes.trim();

      await apiPost(`/api/v1/clients/${user.id}/profile`, profilePayload);

      // Step 3: Assign client role
      const rolePayload: RoleAssignmentRequest = {
        user_id: user.id,
        role: "client",
      };
      await apiPost(`/api/v1/users/${user.id}/roles`, rolePayload);
    },
    onSuccess: () => {
      toast.success("Client created");
      queryClient.invalidateQueries({ queryKey: ["clients"] });
      onOpenChange(false);
      setForm(INITIAL_FORM);
      setErrors({});
    },
    onError: (err: Error) => {
      const message = err.message || "Failed to create client";
      toast.error(message);
    },
  });

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!validate()) return;
    mutation.mutate();
  }

  function handleChange(field: keyof CreateClientFormData, value: string) {
    setForm((prev) => ({ ...prev, [field]: value }));
    if (errors[field]) {
      setErrors((prev) => {
        const next = { ...prev };
        delete next[field];
        return next;
      });
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        onOpenChange(nextOpen);
        if (!nextOpen) {
          setForm(INITIAL_FORM);
          setErrors({});
          mutation.reset();
        }
      }}
    >
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Create Client</DialogTitle>
            <DialogDescription>
              Add a new client to the system. Required fields are marked with *.
            </DialogDescription>
          </DialogHeader>

          <div className="grid gap-4 py-4">
            {/* Email */}
            <div className="grid gap-1.5">
              <Label htmlFor="email">Email *</Label>
              <Input
                id="email"
                type="email"
                placeholder="client@example.com"
                value={form.email}
                onChange={(e) => handleChange("email", e.target.value)}
                aria-invalid={!!errors.email}
              />
              {errors.email && (
                <p className="text-xs text-destructive">{errors.email}</p>
              )}
            </div>

            {/* First Name */}
            <div className="grid gap-1.5">
              <Label htmlFor="first_name">First Name *</Label>
              <Input
                id="first_name"
                placeholder="Jane"
                value={form.first_name}
                onChange={(e) => handleChange("first_name", e.target.value)}
                aria-invalid={!!errors.first_name}
              />
              {errors.first_name && (
                <p className="text-xs text-destructive">{errors.first_name}</p>
              )}
            </div>

            {/* Last Name */}
            <div className="grid gap-1.5">
              <Label htmlFor="last_name">Last Name *</Label>
              <Input
                id="last_name"
                placeholder="Doe"
                value={form.last_name}
                onChange={(e) => handleChange("last_name", e.target.value)}
                aria-invalid={!!errors.last_name}
              />
              {errors.last_name && (
                <p className="text-xs text-destructive">{errors.last_name}</p>
              )}
            </div>

            {/* Phone */}
            <div className="grid gap-1.5">
              <Label htmlFor="phone">Phone</Label>
              <Input
                id="phone"
                placeholder="(555) 123-4567"
                value={form.phone}
                onChange={(e) => handleChange("phone", e.target.value)}
              />
            </div>

            {/* Billing Address */}
            <div className="grid gap-1.5">
              <Label htmlFor="billing_address">Billing Address</Label>
              <Textarea
                id="billing_address"
                placeholder="123 Main St, City, State ZIP"
                value={form.billing_address}
                onChange={(e) => handleChange("billing_address", e.target.value)}
              />
            </div>

            {/* Tags */}
            <div className="grid gap-1.5">
              <Label htmlFor="tags">Tags</Label>
              <Input
                id="tags"
                placeholder="vip, commercial, repeat"
                value={form.tags}
                onChange={(e) => handleChange("tags", e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                Separate tags with commas
              </p>
            </div>

            {/* Admin Notes */}
            <div className="grid gap-1.5">
              <Label htmlFor="admin_notes">Admin Notes</Label>
              <Textarea
                id="admin_notes"
                placeholder="Internal notes about this client..."
                value={form.admin_notes}
                onChange={(e) => handleChange("admin_notes", e.target.value)}
              />
            </div>
          </div>

          <DialogFooter>
            <Button type="submit" disabled={mutation.isPending}>
              {mutation.isPending ? "Creating..." : "Create Client"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
