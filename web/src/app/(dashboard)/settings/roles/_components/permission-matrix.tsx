"use client";

import { useMemo, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Check, Lock, RotateCcw, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { apiGet, apiPut, apiPost } from "@/lib/api-client";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { ROLE_SLUGS, ROLE_LABELS, type Role } from "@/lib/roles";
import type { RolePermissionsResponse } from "@/types/api";

const OWNER: Role = "owner";
const EDITABLE_ROLES = ROLE_SLUGS.filter((role) => role !== OWNER);

type RoleMap = Record<string, Set<string>>;

function toRoleMap(roles: Record<string, string[]>): RoleMap {
  return Object.fromEntries(Object.entries(roles).map(([role, keys]) => [role, new Set(keys)]));
}

function sameKeys(a: Set<string>, b: string[]): boolean {
  return a.size === b.length && b.every((key) => a.has(key));
}

/** Owner/admin editor for the per-company role -> permission matrix. */
export function PermissionMatrix() {
  const queryClient = useQueryClient();
  const { data, isLoading, isError } = useQuery<RolePermissionsResponse>({
    queryKey: ["role-permissions"],
    queryFn: () => apiGet<RolePermissionsResponse>("/api/v1/roles/permissions"),
  });

  const [edited, setEdited] = useState<RoleMap>({});
  const [syncedRoles, setSyncedRoles] = useState<Record<string, string[]> | null>(null);

  // Reset local edits when fresh server data arrives (React's render-time
  // "adjust state when a prop changes" pattern — no effect needed). data.roles
  // is a new reference on every fetch, so this fires once per load/refetch.
  if (data && data.roles !== syncedRoles) {
    setSyncedRoles(data.roles);
    setEdited(toRoleMap(data.roles));
  }

  const groups = useMemo(() => {
    const order: string[] = [];
    const byGroup = new Map<string, RolePermissionsResponse["catalog"]>();
    for (const item of data?.catalog ?? []) {
      if (!byGroup.has(item.group)) {
        byGroup.set(item.group, []);
        order.push(item.group);
      }
      byGroup.get(item.group)!.push(item);
    }
    return order.map((group) => ({ group, items: byGroup.get(group)! }));
  }, [data]);

  const dirtyRoles = useMemo(() => {
    if (!data) return [];
    return EDITABLE_ROLES.filter(
      (role) => edited[role] && !sameKeys(edited[role], data.roles[role] ?? [])
    );
  }, [edited, data]);

  const saveMutation = useMutation({
    mutationFn: async (roles: Role[]) => {
      for (const role of roles) {
        await apiPut(`/api/v1/roles/${role}/permissions`, {
          permissions: Array.from(edited[role]),
        });
      }
    },
    onSuccess: async (_result, roles) => {
      await queryClient.invalidateQueries({ queryKey: ["role-permissions"] });
      await queryClient.invalidateQueries({ queryKey: ["me-permissions"] });
      toast.success(`Saved ${roles.length} role${roles.length === 1 ? "" : "s"}`);
    },
    onError: (error: Error) => toast.error(error.message || "Could not save permissions"),
  });

  const resetMutation = useMutation({
    mutationFn: () => apiPost("/api/v1/roles/permissions/reset", {}),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["role-permissions"] });
      await queryClient.invalidateQueries({ queryKey: ["me-permissions"] });
      toast.success("Restored default permissions");
    },
    onError: (error: Error) => toast.error(error.message || "Could not reset permissions"),
  });

  const busy = saveMutation.isPending || resetMutation.isPending;

  function toggle(role: Role, key: string) {
    setEdited((prev) => {
      const next = new Set(prev[role]);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return { ...prev, [role]: next };
    });
  }

  function isChecked(role: Role, key: string): boolean {
    if (role === OWNER) return true; // owner holds the wildcard — always on
    return edited[role]?.has(key) ?? false;
  }

  function modifiedFromDefault(role: Role): boolean {
    if (!data || role === OWNER) return false;
    return !sameKeys(edited[role] ?? new Set(), data.defaults[role] ?? []);
  }

  if (isLoading) {
    return <div className="h-64 animate-pulse rounded-lg bg-muted" />;
  }
  if (isError || !data) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 px-6 py-8 text-center text-sm text-red-700">
        Could not load role permissions. Try refreshing the page.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          Toggle what each role can do. Changes apply the moment you save. The{" "}
          <span className="font-medium text-foreground">Owner</span> role always has full access.
        </p>
        <Button
          variant="outline"
          size="sm"
          onClick={() => resetMutation.mutate()}
          disabled={busy}
        >
          <RotateCcw className="mr-1.5 h-3.5 w-3.5" />
          Reset to defaults
        </Button>
      </div>

      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="bg-secondary/60">
              <th className="sticky left-0 z-10 bg-secondary/60 px-4 py-3 text-left font-semibold">
                Permission
              </th>
              {ROLE_SLUGS.map((role) => (
                <th
                  key={role}
                  className="min-w-[92px] px-2 py-3 text-center align-bottom font-semibold"
                >
                  <span className="flex flex-col items-center gap-1">
                    <span className="flex items-center gap-1">
                      {role === OWNER && <Lock className="h-3 w-3 text-muted-foreground" />}
                      {ROLE_LABELS[role]}
                    </span>
                    {modifiedFromDefault(role) && (
                      <span
                        className="h-1.5 w-1.5 rounded-full bg-brand"
                        title="Modified from default"
                      />
                    )}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {groups.map(({ group, items }) => (
              <PermissionGroup
                key={group}
                group={group}
                items={items}
                isChecked={isChecked}
                onToggle={toggle}
              />
            ))}
          </tbody>
        </table>
      </div>

      {/* Sticky save bar — only when there are unsaved edits */}
      {dirtyRoles.length > 0 && (
        <div className="sticky bottom-4 z-20 flex items-center justify-between gap-3 rounded-lg border border-brand/40 bg-background px-4 py-3 shadow-lg">
          <span className="text-sm font-medium">
            {dirtyRoles.length} role{dirtyRoles.length === 1 ? "" : "s"} changed
          </span>
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setEdited(toRoleMap(data.roles))}
              disabled={busy}
            >
              Discard
            </Button>
            <Button
              variant="brand"
              size="sm"
              onClick={() => saveMutation.mutate(dirtyRoles)}
              disabled={busy}
            >
              {saveMutation.isPending && <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
              Save changes
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}

interface PermissionGroupProps {
  group: string;
  items: RolePermissionsResponse["catalog"];
  isChecked: (role: Role, key: string) => boolean;
  onToggle: (role: Role, key: string) => void;
}

function PermissionGroup({ group, items, isChecked, onToggle }: PermissionGroupProps) {
  return (
    <>
      <tr>
        <td
          colSpan={ROLE_SLUGS.length + 1}
          className="sticky left-0 bg-muted/50 px-4 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground"
        >
          {group}
        </td>
      </tr>
      {items.map((item) => (
        <tr key={item.key} className="border-t border-border/60 hover:bg-secondary/30">
          <td className="sticky left-0 z-10 bg-background px-4 py-2">
            <span className="block font-medium text-foreground">{item.label}</span>
            <span className="block font-mono text-[11px] text-muted-foreground">{item.key}</span>
          </td>
          {ROLE_SLUGS.map((role) => {
            const checked = isChecked(role, item.key);
            const locked = role === OWNER;
            return (
              <td key={role} className="px-2 py-2 text-center">
                <button
                  type="button"
                  disabled={locked}
                  aria-pressed={checked}
                  aria-label={`${ROLE_LABELS[role]}: ${item.label}`}
                  onClick={() => onToggle(role, item.key)}
                  className={cn(
                    "inline-flex h-5 w-5 items-center justify-center rounded-[4px] border transition-colors",
                    checked
                      ? "border-brand bg-brand text-brand-foreground"
                      : "border-border bg-transparent hover:border-brand/60",
                    locked && "cursor-not-allowed opacity-60"
                  )}
                >
                  {checked && <Check className="h-3.5 w-3.5" />}
                </button>
              </td>
            );
          })}
        </tr>
      ))}
    </>
  );
}
