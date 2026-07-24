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
import { ROLE_LABELS, STAFF_ROLE_SLUGS, type Role } from "@/lib/roles";
import type { UserCreateRequest, RoleAssignmentRequest } from "@/types/api";

interface CreatedUser {
  id: string;
  email: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
}

interface CreateUserDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CreateUserDialog({ open, onOpenChange }: CreateUserDialogProps) {
  const [email, setEmail] = useState("");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [phone, setPhone] = useState("");
  const [role, setRole] = useState<Role | "">("");
  const [formError, setFormError] = useState<string | null>(null);

  const queryClient = useQueryClient();

  const resetForm = () => {
    setEmail("");
    setFirstName("");
    setLastName("");
    setPhone("");
    setRole("");
    setFormError(null);
  };

  const mutation = useMutation({
    mutationFn: async (assignedRole: Role) => {
      // Step 1: create the user
      const body: UserCreateRequest = {
        email,
        first_name: firstName,
        last_name: lastName,
      };
      if (phone.trim()) body.phone = phone.trim();
      const user = await apiPost<CreatedUser>("/api/v1/users/", body);

      // Step 2: assign the selected role
      const roleBody: RoleAssignmentRequest = { user_id: user.id, role: assignedRole };
      await apiPost(`/api/v1/users/${user.id}/roles`, roleBody);

      return user;
    },
    onSuccess: () => {
      toast.success("Team member added");
      queryClient.invalidateQueries({ queryKey: ["users"] });
      onOpenChange(false);
      resetForm();
    },
    onError: (error: Error) => {
      const message =
        "detail" in error ? (error as { detail: string }).detail : error.message;
      setFormError(message || "Failed to create user");
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);

    if (!email.trim()) return setFormError("Email is required");
    if (!firstName.trim()) return setFormError("First name is required");
    if (!lastName.trim()) return setFormError("Last name is required");
    if (!role) return setFormError("Role is required");

    mutation.mutate(role);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Team Member</DialogTitle>
            <DialogDescription>
              Create a new team member account. They will receive an email to set
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
              <Label htmlFor="user-email">
                Email <span className="text-destructive">*</span>
              </Label>
              <Input
                id="user-email"
                type="email"
                placeholder="teammate@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-2">
                <Label htmlFor="user-first-name">
                  First Name <span className="text-destructive">*</span>
                </Label>
                <Input
                  id="user-first-name"
                  type="text"
                  placeholder="Jane"
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  required
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="user-last-name">
                  Last Name <span className="text-destructive">*</span>
                </Label>
                <Input
                  id="user-last-name"
                  type="text"
                  placeholder="Walsh"
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                  required
                />
              </div>
            </div>

            <div className="grid gap-2">
              <Label htmlFor="user-phone">Phone</Label>
              <Input
                id="user-phone"
                type="tel"
                placeholder="+1 (555) 123-4567"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
              />
            </div>

            <div className="grid gap-2">
              <Label htmlFor="user-role">
                Role <span className="text-destructive">*</span>
              </Label>
              <Select value={role} onValueChange={(v) => setRole((v as Role) ?? "")}>
                <SelectTrigger id="user-role" className="w-full">
                  <SelectValue placeholder="Select a role..." />
                </SelectTrigger>
                <SelectContent>
                  {STAFF_ROLE_SLUGS.map((slug) => (
                    <SelectItem key={slug} value={slug}>
                      {ROLE_LABELS[slug]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <DialogFooter>
            <Button type="submit" disabled={mutation.isPending}>
              {mutation.isPending ? "Creating..." : "Create User"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
