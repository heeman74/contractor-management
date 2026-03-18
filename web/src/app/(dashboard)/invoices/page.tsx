"use client";

import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { Search, ArrowUpDown, ArrowUp, ArrowDown } from "lucide-react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { apiGet } from "@/lib/api-client";
import { StatusBadge } from "@/components/shared/status-badge";
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
import type { Invoice, Job } from "@/types/api";

const PAGE_SIZE = 25;

type SortCol = "invoice_number" | "total" | "amount_paid" | "due_date" | "status";
type SortDir = "asc" | "desc";

const INVOICE_STATUS_TABS: { label: string; value: string }[] = [
  { label: "All", value: "all" },
  { label: "Unpaid", value: "unpaid" },
  { label: "Partially Paid", value: "partially_paid" },
  { label: "Paid", value: "paid" },
  { label: "Overdue", value: "overdue" },
  { label: "Draft", value: "draft" },
];

function isOverdue(invoice: Invoice): boolean {
  return (
    (invoice.status === "unpaid" || invoice.status === "partially_paid") &&
    invoice.due_date !== null &&
    new Date(invoice.due_date) < new Date()
  );
}

function sortInvoices(
  invoices: Invoice[],
  col: SortCol,
  dir: SortDir
): Invoice[] {
  return [...invoices].sort((a, b) => {
    let valA: string | number = "";
    let valB: string | number = "";

    switch (col) {
      case "invoice_number":
        valA = a.invoice_number.toLowerCase();
        valB = b.invoice_number.toLowerCase();
        break;
      case "total":
        valA = Number(a.total);
        valB = Number(b.total);
        break;
      case "amount_paid":
        valA = Number(a.amount_paid);
        valB = Number(b.amount_paid);
        break;
      case "due_date":
        valA = a.due_date ?? "";
        valB = b.due_date ?? "";
        break;
      case "status":
        valA = a.status;
        valB = b.status;
        break;
    }

    if (valA < valB) return dir === "asc" ? -1 : 1;
    if (valA > valB) return dir === "asc" ? 1 : -1;
    return 0;
  });
}

// Default export wraps with Suspense boundary required by Next.js for useSearchParams()
export default function InvoicesPage() {
  return (
    <Suspense>
      <InvoicesPageContent />
    </Suspense>
  );
}

function InvoicesPageContent() {
  const searchParams = useSearchParams();
  const router = useRouter();

  const activeTab = searchParams.get("tab") ?? "all";
  const page = parseInt(searchParams.get("page") ?? "1", 10);
  const searchQuery = searchParams.get("q") ?? "";
  const sortCol = (searchParams.get("sort") ?? "due_date") as SortCol;
  const sortDir = (searchParams.get("dir") ?? "desc") as SortDir;

  const [searchInput, setSearchInput] = useState(searchQuery);
  const [debouncedSearch, setDebouncedSearch] = useState(searchQuery);
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Keep searchInput in sync with URL param on initial load / back-nav
  useEffect(() => {
    setSearchInput(searchQuery);
    setDebouncedSearch(searchQuery);
  }, [searchQuery]);

  const handleSearchChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const value = e.target.value;
      setSearchInput(value);

      if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = setTimeout(() => {
        setDebouncedSearch(value);
        const params = new URLSearchParams(searchParams.toString());
        if (value) {
          params.set("q", value);
        } else {
          params.delete("q");
        }
        params.set("page", "1");
        router.replace(`/invoices?${params.toString()}`);
      }, 300);
    },
    [router, searchParams]
  );

  const handleTabChange = useCallback(
    (tab: string) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set("tab", tab);
      params.set("page", "1");
      router.push(`/invoices?${params.toString()}`);
    },
    [router, searchParams]
  );

  const handleSortChange = useCallback(
    (col: SortCol) => {
      const params = new URLSearchParams(searchParams.toString());
      if (sortCol === col) {
        params.set("dir", sortDir === "asc" ? "desc" : "asc");
      } else {
        params.set("sort", col);
        params.set("dir", "desc");
      }
      params.set("page", "1");
      router.push(`/invoices?${params.toString()}`);
    },
    [router, searchParams, sortCol, sortDir]
  );

  const handlePageChange = useCallback(
    (newPage: number) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set("page", String(newPage));
      router.push(`/invoices?${params.toString()}`);
    },
    [router, searchParams]
  );

  // Fetch all invoices
  const {
    data: invoices,
    isLoading,
    isError,
  } = useQuery({
    queryKey: ["invoices"],
    queryFn: () => apiGet<Invoice[]>("/api/v1/invoices/"),
  });

  // Fetch jobs for client name and description lookups
  const { data: jobs } = useQuery({
    queryKey: ["jobs"],
    queryFn: () => apiGet<Job[]>("/api/v1/jobs"),
  });

  // Build jobsMap: job_id -> Job
  const jobsMap: Record<string, Job> = {};
  if (jobs) {
    for (const job of jobs) {
      jobsMap[job.id] = job;
    }
  }

  // Error handling
  if (isError) {
    toast.error("Failed to load invoices. Check your connection and try again.", {
      duration: Infinity,
    });
  }

  // Client-side filtering by tab
  const allInvoices = invoices ?? [];

  function filterByTab(inv: Invoice[]): Invoice[] {
    if (activeTab === "all") return inv;
    if (activeTab === "overdue") return inv.filter(isOverdue);
    // "draft" is a display tab — invoices without finalized_at could be considered draft
    // but InvoiceStatus doesn't have "draft" as a backend status.
    // Map draft tab to invoices where finalized_at is null and status is unpaid.
    if (activeTab === "draft") {
      return inv.filter((i) => i.finalized_at === null);
    }
    return inv.filter((i) => i.status === activeTab);
  }

  // Client-side search
  function applySearch(inv: Invoice[]): Invoice[] {
    if (!debouncedSearch) return inv;
    const q = debouncedSearch.toLowerCase();
    return inv.filter((invoice) => {
      const job = jobsMap[invoice.job_id];
      return (
        invoice.invoice_number.toLowerCase().includes(q) ||
        (job?.description?.toLowerCase().includes(q) ?? false) ||
        (job?.client_name?.toLowerCase().includes(q) ?? false)
      );
    });
  }

  // Tab counts
  function getTabCount(tabValue: string): number {
    const inv = invoices ?? [];
    if (tabValue === "all") return inv.length;
    if (tabValue === "overdue") return inv.filter(isOverdue).length;
    if (tabValue === "draft") return inv.filter((i) => i.finalized_at === null).length;
    return inv.filter((i) => i.status === tabValue).length;
  }

  const filtered = filterByTab(allInvoices);
  const searched = applySearch(filtered);
  const sorted = sortInvoices(searched, sortCol, sortDir);

  // Pagination
  const startIdx = (page - 1) * PAGE_SIZE;
  const paginated = sorted.slice(startIdx, startIdx + PAGE_SIZE);

  function SortIcon({ col }: { col: SortCol }) {
    if (sortCol !== col) {
      return <ArrowUpDown className="ml-1 inline h-3 w-3 text-gray-400" />;
    }
    return sortDir === "asc" ? (
      <ArrowUp className="ml-1 inline h-3 w-3 text-gray-700" />
    ) : (
      <ArrowDown className="ml-1 inline h-3 w-3 text-gray-700" />
    );
  }

  return (
    <div className="space-y-4">
      {/* Header row: page title + search bar */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-gray-900">Invoices</h1>
        <div className="relative w-72">
          <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 pointer-events-none" />
          <Input
            className="pl-8"
            placeholder="Search invoices..."
            value={searchInput}
            onChange={handleSearchChange}
          />
        </div>
      </div>

      {/* Status tab bar */}
      <div className="flex items-center border-b border-gray-200">
        {INVOICE_STATUS_TABS.map((tab) => {
          const count = getTabCount(tab.value);
          const isActive = activeTab === tab.value;
          return (
            <button
              key={tab.value}
              onClick={() => handleTabChange(tab.value)}
              className={`py-3 px-4 text-sm transition-colors whitespace-nowrap ${
                isActive
                  ? "border-b-2 border-gray-900 text-gray-900 font-semibold -mb-px"
                  : "text-gray-500 hover:text-gray-700"
              }`}
            >
              {tab.label}
              {invoices !== undefined && (
                <span className="text-xs text-gray-400 ml-1">({count})</span>
              )}
            </button>
          );
        })}
      </div>

      {/* Data table */}
      <div className="rounded-xl bg-white ring-1 ring-foreground/10 overflow-hidden">
        {isLoading ? (
          <SkeletonRows />
        ) : paginated.length === 0 ? (
          <EmptyState
            title={
              activeTab === "all" && !debouncedSearch
                ? "No invoices yet"
                : `No ${activeTab.replace(/_/g, " ")} invoices`
            }
            message={
              activeTab === "all" && !debouncedSearch
                ? "Invoices are generated from approved quotes. Approve a quote to create an invoice."
                : `No invoices match the current filter.`
            }
          />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                  onClick={() => handleSortChange("invoice_number")}
                >
                  Invoice #
                  <SortIcon col="invoice_number" />
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Job
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Client
                </TableHead>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide text-right cursor-pointer select-none"
                  onClick={() => handleSortChange("total")}
                >
                  Total
                  <SortIcon col="total" />
                </TableHead>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide text-right cursor-pointer select-none"
                  onClick={() => handleSortChange("amount_paid")}
                >
                  Paid
                  <SortIcon col="amount_paid" />
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide text-right">
                  Balance
                </TableHead>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                  onClick={() => handleSortChange("status")}
                >
                  Status
                  <SortIcon col="status" />
                </TableHead>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                  onClick={() => handleSortChange("due_date")}
                >
                  Due Date
                  <SortIcon col="due_date" />
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {paginated.map((invoice) => {
                const overdue = isOverdue(invoice);
                const job = jobsMap[invoice.job_id];
                const balance =
                  Number(invoice.total) - Number(invoice.amount_paid);
                return (
                  <TableRow
                    key={invoice.id}
                    className={cn(
                      "cursor-pointer hover:bg-gray-50",
                      overdue && "border-l-2 border-red-400"
                    )}
                    onClick={() => router.push(`/invoices/${invoice.id}`)}
                  >
                    <TableCell className="py-3 px-4 font-mono text-sm text-gray-900">
                      {invoice.invoice_number}
                    </TableCell>
                    <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-[140px]">
                      {job?.description ?? "—"}
                    </TableCell>
                    <TableCell className="py-3 px-4 text-sm text-gray-700">
                      {job?.client_name ?? "—"}
                    </TableCell>
                    <TableCell className="py-3 px-4 font-mono text-sm text-gray-900 text-right">
                      ${Number(invoice.total).toFixed(2)}
                    </TableCell>
                    <TableCell className="py-3 px-4 font-mono text-sm text-green-700 text-right">
                      ${Number(invoice.amount_paid).toFixed(2)}
                    </TableCell>
                    <TableCell
                      className={cn(
                        "py-3 px-4 font-mono text-sm text-right",
                        overdue ? "text-red-700" : "text-gray-900"
                      )}
                    >
                      ${balance.toFixed(2)}
                    </TableCell>
                    <TableCell className="py-3 px-4">
                      <StatusBadge
                        status={overdue ? "overdue" : invoice.status}
                        size="sm"
                      />
                    </TableCell>
                    <TableCell
                      className={cn(
                        "py-3 px-4 text-sm",
                        overdue
                          ? "text-red-600 font-medium"
                          : "text-gray-500"
                      )}
                    >
                      {invoice.due_date
                        ? new Date(invoice.due_date).toLocaleDateString()
                        : "—"}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </div>

      {/* Pagination */}
      <div className="flex items-center justify-between">
        <span className="text-sm text-gray-500">
          Showing page {page} of {Math.max(1, Math.ceil(sorted.length / PAGE_SIZE))}
        </span>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => handlePageChange(page - 1)}
            disabled={page === 1}
          >
            Previous
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => handlePageChange(page + 1)}
            disabled={startIdx + PAGE_SIZE >= sorted.length}
          >
            Next
          </Button>
        </div>
      </div>
    </div>
  );
}

function SkeletonRows() {
  return (
    <div className="divide-y">
      {[...Array(5)].map((_, i) => (
        <div key={i} className="flex items-center gap-4 px-4 h-12">
          <Skeleton className="h-4 w-24" />
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-4 w-24" />
          <Skeleton className="h-4 w-16" />
          <Skeleton className="h-4 w-16" />
          <Skeleton className="h-4 w-16" />
          <Skeleton className="h-4 w-20" />
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
