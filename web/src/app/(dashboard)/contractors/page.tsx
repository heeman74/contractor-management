"use client";

import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { Search, ArrowUp, ArrowDown, Plus } from "lucide-react";
import { toast } from "sonner";
import { apiGet, apiPost } from "@/lib/api-client";
import { StatusBadge } from "@/components/shared/status-badge";
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
import type { ContractorListItem, AvailabilityResponse } from "@/types/api";
import { CreateContractorDialog } from "./_components/create-contractor-dialog";

const PAGE_SIZE = 50;

type SortDir = "asc" | "desc";

function getAvailabilityStatus(
  contractorId: string,
  availabilityData: AvailabilityResponse[] | undefined
): "available" | "partially_booked" | "fully_booked" {
  const avail = availabilityData?.find((a) => a.contractor_id === contractorId);
  if (!avail || avail.free_windows.length === 0) return "fully_booked";
  // Sum total free minutes
  const totalFreeMinutes = avail.free_windows.reduce((sum, w) => {
    const start = new Date(w.start).getTime();
    const end = new Date(w.end).getTime();
    return sum + (end - start) / 60000;
  }, 0);
  return totalFreeMinutes >= 240 ? "available" : "partially_booked"; // 4 hours = 240 min
}

export default function ContractorsPage() {
  const router = useRouter();

  const [searchInput, setSearchInput] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const [page, setPage] = useState(1);
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Query 1: Fetch all users
  const {
    data: allUsers,
    isLoading: usersLoading,
    isError: usersError,
  } = useQuery({
    queryKey: ["users"],
    queryFn: () => apiGet<ContractorListItem[]>("/api/v1/users/"),
  });

  // Filter to contractors client-side
  const contractors = useMemo(
    () => allUsers?.filter((u) => u.roles.includes("contractor")) ?? [],
    [allUsers]
  );

  // Apply client-side search filter
  const filteredContractors = useMemo(() => {
    if (!debouncedSearch) return contractors;
    const lower = debouncedSearch.toLowerCase();
    return contractors.filter(
      (c) =>
        `${c.first_name ?? ""} ${c.last_name ?? ""}`.toLowerCase().includes(lower) ||
        c.email.toLowerCase().includes(lower)
    );
  }, [contractors, debouncedSearch]);

  // Sort by name
  const sortedContractors = useMemo(() => {
    return [...filteredContractors].sort((a, b) => {
      const nameA = `${a.first_name ?? ""} ${a.last_name ?? ""}`.toLowerCase().trim();
      const nameB = `${b.first_name ?? ""} ${b.last_name ?? ""}`.toLowerCase().trim();
      if (nameA < nameB) return sortDir === "asc" ? -1 : 1;
      if (nameA > nameB) return sortDir === "asc" ? 1 : -1;
      return 0;
    });
  }, [filteredContractors, sortDir]);

  // Paginate
  const totalPages = Math.max(1, Math.ceil(sortedContractors.length / PAGE_SIZE));
  const pagedContractors = sortedContractors.slice(
    (page - 1) * PAGE_SIZE,
    page * PAGE_SIZE
  );

  // Query 2: Batch availability for all visible contractor IDs
  const contractorIds = pagedContractors.map((c) => c.id);
  const todayStr = new Date().toISOString().split("T")[0];
  const { data: availabilityData } = useQuery({
    queryKey: ["availability-today", contractorIds],
    queryFn: () =>
      apiPost<AvailabilityResponse[]>("/api/v1/scheduling/availability", {
        contractor_ids: contractorIds,
        date: todayStr,
      }),
    enabled: contractorIds.length > 0,
  });

  const handleSearchChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const value = e.target.value;
      setSearchInput(value);
      if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = setTimeout(() => {
        setDebouncedSearch(value);
        setPage(1);
      }, 300);
    },
    []
  );

  const handleSortToggle = useCallback(() => {
    setSortDir((prev) => (prev === "asc" ? "desc" : "asc"));
  }, []);

  useEffect(() => {
    if (usersError) {
      toast.error("Failed to load contractors. Please refresh the page.", {
        duration: Infinity,
      });
    }
  }, [usersError]);

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* Header row: page title + search bar + add button */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-gray-900">Contractors</h1>
        <div className="flex items-center gap-3">
          <div className="relative w-72">
            <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 pointer-events-none" />
            <Input
              className="pl-8"
              placeholder="Search by name or email..."
              value={searchInput}
              onChange={handleSearchChange}
            />
          </div>
          <Button onClick={() => setCreateDialogOpen(true)}>
            <Plus className="h-4 w-4" data-icon="inline-start" />
            Add Contractor
          </Button>
          <CreateContractorDialog open={createDialogOpen} onOpenChange={setCreateDialogOpen} />
        </div>
      </div>

      {/* Data table */}
      <div className="rounded-xl bg-white ring-1 ring-foreground/10 overflow-hidden">
        {usersLoading ? (
          <SkeletonRows />
        ) : contractors.length === 0 ? (
          <EmptyState
            title="No contractors yet"
            message="Contractors will appear here once they are assigned the contractor role."
          />
        ) : filteredContractors.length === 0 ? (
          <EmptyState
            title="No contractors found"
            message="Try a different name or email address."
          />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                  onClick={handleSortToggle}
                >
                  Name
                  {sortDir === "asc" ? (
                    <ArrowUp className="ml-1 inline h-3 w-3 text-gray-700" />
                  ) : (
                    <ArrowDown className="ml-1 inline h-3 w-3 text-gray-700" />
                  )}
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Email
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Phone
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Trade
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Availability
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide text-right">
                  Active Jobs
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pagedContractors.map((contractor) => (
                <TableRow
                  key={contractor.id}
                  className="cursor-pointer hover:bg-gray-50"
                  onClick={() => router.push(`/contractors/${contractor.id}`)}
                >
                  <TableCell className="py-3 px-4 font-medium text-sm text-gray-900">
                    {contractor.first_name || contractor.last_name
                      ? `${contractor.first_name ?? ""} ${contractor.last_name ?? ""}`.trim()
                      : "—"}
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-700">
                    {contractor.email}
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-500">
                    {contractor.phone ?? "—"}
                  </TableCell>
                  <TableCell className="py-3 px-4">
                    <Badge className="bg-gray-100 text-gray-700 border-0">
                      Contractor
                    </Badge>
                  </TableCell>
                  <TableCell className="py-3 px-4">
                    <StatusBadge
                      status={getAvailabilityStatus(contractor.id, availabilityData)}
                      size="sm"
                    />
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-500 text-right">
                    —
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </div>

      {/* Pagination */}
      {sortedContractors.length > 0 && (
        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-500">
            Showing {Math.min((page - 1) * PAGE_SIZE + 1, sortedContractors.length)}–
            {Math.min(page * PAGE_SIZE, sortedContractors.length)} of{" "}
            {sortedContractors.length} contractors
          </span>
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setPage((p) => p - 1)}
              disabled={page === 1}
            >
              Previous
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => setPage((p) => p + 1)}
              disabled={page >= totalPages}
            >
              Next
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}

function SkeletonRows() {
  return (
    <div className="divide-y">
      {[...Array(10)].map((_, i) => (
        <div key={i} className="flex items-center gap-4 px-4 h-12">
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-4 w-40" />
          <Skeleton className="h-4 w-24" />
          <Skeleton className="h-4 w-16" />
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
