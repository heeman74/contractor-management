"use client";

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ROLE_SLUGS, ROLE_LABELS, type Role } from "@/lib/roles";

interface RoleSelectProps {
  value: Role;
  onChange: (role: Role) => void;
  /** Roles to omit from the list (e.g. roles a user already holds). */
  exclude?: Role[];
  id?: string;
  className?: string;
}

/** Reusable single-role picker over the eight canonical roles. */
export function RoleSelect({ value, onChange, exclude = [], id, className }: RoleSelectProps) {
  const options = ROLE_SLUGS.filter((role) => !exclude.includes(role));

  return (
    <Select value={value} onValueChange={(v) => onChange(v as Role)}>
      <SelectTrigger id={id} className={className}>
        <SelectValue placeholder="Select a role..." />
      </SelectTrigger>
      <SelectContent>
        {options.map((role) => (
          <SelectItem key={role} value={role}>
            {ROLE_LABELS[role]}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
