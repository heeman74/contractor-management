"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { Search, ArrowUpDown, ArrowUp, ArrowDown, Plus } from "lucide-react";
import { apiGet } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { ClientListItem } from "@/types/api";
import { CreateClientDialog } from "./_components/create-client-dialog";

const PAGE_SIZE = 50;

type SortField = "name" | "jobs";
type SortDir = "asc" | "desc";

function sortClients(
  clients: ClientListItem[],
  field: SortField,
  dir: SortDir
): ClientListItem[] {
  return [...clients].sort((a, b) => {
    let valA: string | number = "";
    let valB: string | number = "";

    if (field === "name") {
      valA = `${a.last_name ?? ""} ${a.first_name ?? ""}`.toLowerCase();
      valB = `${b.last_name ?? ""} ${b.first_name ?? ""}`.toLowerCase();
    } else {
      valA = a.jobs_count;
      valB = b.jobs_count;
    }

    if (valA < valB) return dir === "asc" ? -1 : 1;
    if (valA > valB) return dir === "asc" ? 1 : -1;
    return 0;
  });
}

export default function ClientsPage() {
  const router = useRouter();

  const [searchInput, setSearchInput] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [page, setPage] = useState(1);
  const [sortField, setSortField] = useState<SortField>("name");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
    debounceTimerRef.current = setTimeout(() => {
      setDebouncedSearch(searchInput);
      setPage(1);
    }, 300);
    return () => {
      if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
    };
  }, [searchInput]);

  const { data: clients, isLoading, isError } = useQuery({
    queryKey: ["clients", { search: debouncedSearch, page, sortField, sortDir }],
    queryFn: () => {
      const params = new URLSearchParams();
      if (debouncedSearch) params.set("search", debouncedSearch);
      params.set("offset", String((page - 1) * PAGE_SIZE));
      params.set("limit", String(PAGE_SIZE));
      return apiGet<ClientListItem[]>(`/api/v1/crm/clients?${params}`);
    },
  });

  function handleSortChange(field: SortField) {
    if (sortField === field) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortField(field);
      setSortDir("asc");
    }
    setPage(1);
  }

  const sortedClients = clients ? sortClients(clients, sortField, sortDir) : [];

  function renderSortIcon(field: SortField) {
    if (sortField !== field) {
      return <ArrowUpDown className="ml-1 inline h-3 w-3 text-gray-400" />;
    }
    return sortDir === "asc" ? (
      <ArrowUp className="ml-1 inline h-3 w-3 text-gray-700" />
    ) : (
      <ArrowDown className="ml-1 inline h-3 w-3 text-gray-700" />
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between gap-4">
        <h1 className="text-2xl font-bold leading-tight">Clients</h1>
        <div className="flex items-center gap-3">
          <div className="relative max-w-sm w-full">
            <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 pointer-events-none" />
            <Input
              className="pl-8"
              placeholder="Search by name or email..."
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
            />
          </div>
          <Button onClick={() => setCreateDialogOpen(true)}>
            <Plus className="h-4 w-4" data-icon="inline-start" />
            New Client
          </Button>
          <CreateClientDialog open={createDialogOpen} onOpenChange={setCreateDialogOpen} />
        </div>
      </div>

      {/* Table */}
      <div className="rounded-xl bg-white ring-1 ring-foreground/10 overflow-hidden">
        {isLoading ? (
          <div className="divide-y">
            {[...Array(10)].map((_, i) => (
              <div key={i} className="flex items-center gap-4 px-4 h-10">
                <Skeleton className="h-10 w-full" />
              </div>
            ))}
          </div>
        ) : isError ? (
          <p className="text-center py-12 text-muted-foreground">
            Failed to load clients. Please refresh the page.
          </p>
        ) : !sortedClients || sortedClients.length === 0 ? (
          <div className="px-4 py-12 text-center">
            {debouncedSearch ? (
              <>
                <p className="text-sm font-medium text-gray-900">No clients found</p>
                <p className="mt-1 text-sm text-gray-500">
                  Try a different name or email address.
                </p>
              </>
            ) : (
              <>
                <p className="text-sm font-medium text-gray-900">No clients yet</p>
                <p className="mt-1 text-sm text-gray-500">
                  Clients will appear here once they submit a job request or are added to the
                  system.
                </p>
              </>
            )}
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                  onClick={() => handleSortChange("name")}
                >
                  Name
                  {renderSortIcon("name")}
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Email
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Phone
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Tags
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Preferred Contractor
                </TableHead>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide text-right cursor-pointer select-none"
                  onClick={() => handleSortChange("jobs")}
                >
                  Jobs
                  {renderSortIcon("jobs")}
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sortedClients.map((client) => (
                <TableRow
                  key={client.id}
                  className="cursor-pointer hover:bg-muted/50"
                  onClick={() => router.push(`/clients/${client.user_id}`)}
                >
                  <TableCell className="py-3 px-4 font-medium text-sm text-gray-900">
                    {client.first_name} {client.last_name}
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-700">
                    {client.email}
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-500">
                    {client.phone ?? "—"}
                  </TableCell>
                  <TableCell className="py-3 px-4">
                    <div className="flex flex-wrap gap-1">
                      {client.tags.map((tag) => (
                        <span
                          key={tag}
                          className="bg-secondary text-foreground text-xs rounded-full px-2 py-0.5"
                        >
                          {tag}
                        </span>
                      ))}
                    </div>
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-500">
                    {client.preferred_contractor_name ?? "—"}
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-700 text-right">
                    {client.jobs_count}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </div>

      {/* Pagination */}
      {!isLoading && !isError && (
        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-500">Page {page}</span>
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
              disabled={!clients || clients.length < PAGE_SIZE}
            >
              Next
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
