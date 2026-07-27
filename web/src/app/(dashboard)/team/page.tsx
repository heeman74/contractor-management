"use client";

import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Search, Plus } from "lucide-react";
import { toast } from "sonner";
import { apiGet } from "@/lib/api-client";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { useCurrentLaborRates } from "@/features/finance/hooks";
import { formatCurrency } from "@/lib/format";
import { ROLE_LABELS, type Role } from "@/lib/roles";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { UserResponse } from "@/types/api";
import { CreateUserDialog } from "./_components/create-user-dialog";
import { RateHistoryDialog } from "./_components/rate-history-dialog";

function fullName(user: UserResponse): string {
  const name = `${user.first_name ?? ""} ${user.last_name ?? ""}`.trim();
  return name || "—";
}

function roleLabel(slug: string): string {
  return ROLE_LABELS[slug as Role] ?? slug;
}

export default function TeamPage() {
  const { can, isLoading: permissionsLoading } = usePermissions();
  const [search, setSearch] = useState("");
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [rateDialogUser, setRateDialogUser] = useState<UserResponse | null>(null);

  const canView = can("users.view");
  const canCreate = can("users.create");
  const canManageRates = can("finance.rates.manage");

  const { data: currentRates, isLoading: ratesLoading } =
    useCurrentLaborRates(canManageRates);
  const rateByUserId = useMemo(
    () => new Map((currentRates ?? []).map((rate) => [rate.userId, rate])),
    [currentRates]
  );

  const {
    data: users,
    isLoading,
    isError,
  } = useQuery({
    queryKey: ["users"],
    queryFn: () => apiGet<UserResponse[]>("/api/v1/users/"),
    enabled: canView,
  });

  const filteredUsers = useMemo(() => {
    const list = users ?? [];
    if (!search.trim()) return list;
    const lower = search.toLowerCase();
    return list.filter(
      (u) =>
        fullName(u).toLowerCase().includes(lower) ||
        u.email.toLowerCase().includes(lower)
    );
  }, [users, search]);

  useEffect(() => {
    if (isError) {
      toast.error("Failed to load team members. Please refresh the page.", {
        duration: Infinity,
      });
    }
  }, [isError]);

  if (permissionsLoading) {
    return (
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <Skeleton className="h-8 w-40" />
      </div>
    );
  }

  if (!canView) {
    return (
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="rounded-xl bg-white ring-1 ring-foreground/10 px-4 py-12 text-center">
          <p className="text-sm font-medium text-gray-900">
            You don&apos;t have access to team management
          </p>
          <p className="mt-1 text-sm text-gray-500">
            Ask an owner or admin to grant you the Users permission.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* Header: title + search + add */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-gray-900">Team</h1>
        <div className="flex items-center gap-3">
          <div className="relative w-72">
            <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 pointer-events-none" />
            <Input
              className="pl-8"
              placeholder="Search by name or email..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          {canCreate && (
            <>
              <Button onClick={() => setCreateDialogOpen(true)}>
                <Plus className="h-4 w-4" data-icon="inline-start" />
                Add User
              </Button>
              <CreateUserDialog
                open={createDialogOpen}
                onOpenChange={setCreateDialogOpen}
              />
            </>
          )}
        </div>
      </div>

      {/* Data table */}
      <div className="rounded-xl bg-white ring-1 ring-foreground/10 overflow-hidden">
        {isLoading ? (
          <SkeletonRows />
        ) : (users ?? []).length === 0 ? (
          <EmptyState
            title="No team members yet"
            message="Add your first team member to get started."
          />
        ) : filteredUsers.length === 0 ? (
          <EmptyState
            title="No team members found"
            message="Try a different name or email address."
          />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Name
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Email
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Phone
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Roles
                </TableHead>
                {canManageRates && (
                  <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Cost Rate
                  </TableHead>
                )}
              </TableRow>
            </TableHeader>
            <TableBody>
              {filteredUsers.map((user) => {
                const rate = rateByUserId.get(user.id);
                return (
                  <TableRow key={user.id}>
                    <TableCell className="py-3 px-4 font-medium text-sm text-gray-900">
                      {fullName(user)}
                    </TableCell>
                    <TableCell className="py-3 px-4 text-sm text-gray-700">
                      {user.email}
                    </TableCell>
                    <TableCell className="py-3 px-4 text-sm text-gray-500">
                      {user.phone ?? "—"}
                    </TableCell>
                    <TableCell className="py-3 px-4">
                      <div className="flex flex-wrap gap-1">
                        {user.roles.length === 0 ? (
                          <span className="text-sm text-gray-400">—</span>
                        ) : (
                          user.roles.map((r) => (
                            <Badge
                              key={r}
                              className="bg-gray-100 text-gray-700 border-0"
                            >
                              {roleLabel(r)}
                            </Badge>
                          ))
                        )}
                      </div>
                    </TableCell>
                    {canManageRates && (
                      <TableCell
                        className="py-3 px-4"
                        data-testid={`cost-rate-${user.id}`}
                      >
                        {ratesLoading ? (
                          <Skeleton className="h-4 w-16" />
                        ) : (
                          <div className="flex items-center gap-2">
                            {rate ? (
                              <span className="text-sm text-gray-900">
                                {formatCurrency(rate.hourlyCost)}/hr
                              </span>
                            ) : (
                              <span className="text-sm text-gray-400">—</span>
                            )}
                            <Button
                              variant="ghost"
                              size="sm"
                              data-testid={`manage-rate-${user.id}`}
                              onClick={() => setRateDialogUser(user)}
                            >
                              Manage rate
                            </Button>
                          </div>
                        )}
                      </TableCell>
                    )}
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </div>

      {canManageRates && (
        <RateHistoryDialog
          open={rateDialogUser !== null}
          onOpenChange={(open) => !open && setRateDialogUser(null)}
          userId={rateDialogUser?.id ?? ""}
          memberName={rateDialogUser ? fullName(rateDialogUser) : ""}
        />
      )}
    </div>
  );
}

function SkeletonRows() {
  return (
    <div className="divide-y">
      {[...Array(8)].map((_, i) => (
        <div key={i} className="flex items-center gap-4 px-4 h-12">
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-4 w-40" />
          <Skeleton className="h-4 w-24" />
          <Skeleton className="h-4 w-20" />
        </div>
      ))}
    </div>
  );
}

function EmptyState({ title, message }: { title: string; message: string }) {
  return (
    <div className="px-4 py-12 text-center">
      <p className="text-sm font-medium text-gray-900">{title}</p>
      <p className="mt-1 text-sm text-gray-500">{message}</p>
    </div>
  );
}
