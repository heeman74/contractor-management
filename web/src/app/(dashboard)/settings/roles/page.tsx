"use client";

import { ShieldCheck } from "lucide-react";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { PermissionMatrix } from "./_components/permission-matrix";

export default function RolesSettingsPage() {
  const { can, isLoading } = usePermissions();

  if (isLoading) {
    return <div className="h-64 animate-pulse rounded-lg bg-muted" />;
  }

  if (!can("roles.permissions.manage")) {
    return (
      <div className="rounded-xl border border-yellow-200 bg-yellow-50 px-6 py-12 text-center">
        <p className="text-sm font-medium text-yellow-700">
          You do not have permission to edit role permissions.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <p className="eyebrow text-brand">Access control</p>
        <h1 className="flex items-center gap-2 font-display text-2xl font-bold tracking-tight text-foreground">
          <ShieldCheck className="h-6 w-6" />
          Roles &amp; Permissions
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Control what each role can do across your company.
        </p>
      </div>

      <PermissionMatrix />
    </div>
  );
}
