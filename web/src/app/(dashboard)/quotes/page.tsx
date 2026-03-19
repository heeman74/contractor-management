"use client";

import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { Search, ArrowUpDown, ArrowUp, ArrowDown } from "lucide-react";
import { toast } from "sonner";
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
import type { Quote, QuoteStatus, Job } from "@/types/api";

const PAGE_SIZE = 25;

type SortCol = "id" | "total" | "status" | "created_at";
type SortDir = "asc" | "desc";

const QUOTE_STATUS_TABS: { label: string; value: string }[] = [
  { label: "All", value: "all" },
  { label: "Draft", value: "draft" },
  { label: "Sent", value: "sent" },
  { label: "Viewed", value: "viewed" },
  { label: "Approved", value: "approved" },
  { label: "Declined", value: "declined" },
  { label: "Expired", value: "expired" },
];

const QUOTE_STATUSES: QuoteStatus[] = [
  "draft",
  "sent",
  "viewed",
  "approved",
  "declined",
  "expired",
];

function sortQuotes(quotes: Quote[], col: SortCol, dir: SortDir): Quote[] {
  return [...quotes].sort((a, b) => {
    let valA: string | number = "";
    let valB: string | number = "";

    switch (col) {
      case "id":
        valA = a.id;
        valB = b.id;
        break;
      case "total":
        valA = Number(a.total);
        valB = Number(b.total);
        break;
      case "status":
        valA = a.status;
        valB = b.status;
        break;
      case "created_at":
        valA = a.created_at;
        valB = b.created_at;
        break;
    }

    if (valA < valB) return dir === "asc" ? -1 : 1;
    if (valA > valB) return dir === "asc" ? 1 : -1;
    return 0;
  });
}

// Default export wraps with Suspense boundary required by Next.js for useSearchParams()
export default function QuotesPage() {
  return (
    <Suspense>
      <QuotesPageContent />
    </Suspense>
  );
}

function QuotesPageContent() {
  const searchParams = useSearchParams();
  const router = useRouter();

  const activeTab = searchParams.get("tab") ?? "all";
  const page = parseInt(searchParams.get("page") ?? "1", 10);
  const searchQuery = searchParams.get("q") ?? "";
  const sortCol = (searchParams.get("sort") ?? "created_at") as SortCol;
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
        router.replace(`/quotes?${params.toString()}`);
      }, 300);
    },
    [router, searchParams]
  );

  const handleTabChange = useCallback(
    (tab: string) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set("tab", tab);
      params.set("page", "1");
      router.push(`/quotes?${params.toString()}`);
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
      router.push(`/quotes?${params.toString()}`);
    },
    [router, searchParams, sortCol, sortDir]
  );

  const handlePageChange = useCallback(
    (newPage: number) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set("page", String(newPage));
      router.push(`/quotes?${params.toString()}`);
    },
    [router, searchParams]
  );

  // Fetch all quotes once — filter and count client-side
  const { data: allQuotes, isLoading, isError } = useQuery({
    queryKey: ["quotes"],
    queryFn: () => apiGet<Quote[]>("/api/v1/quotes/"),
  });

  // Fetch jobs for lookup map (job description + client name)
  const { data: allJobs } = useQuery({
    queryKey: ["jobs-all"],
    queryFn: () => apiGet<Job[]>("/api/v1/jobs/"),
  });

  // Error handling
  useEffect(() => {
    if (isError) {
      toast.error("Failed to load quotes. Check your connection and try again.", {
        duration: Infinity,
      });
    }
  }, [isError]);

  // Build jobs lookup map
  const jobsMap: Record<string, Job> = {};
  if (allJobs) {
    for (const job of allJobs) {
      jobsMap[job.id] = job;
    }
  }

  // Derive per-status counts from the full list
  const countMap: Record<string, number> = {};
  if (allQuotes) {
    for (const status of QUOTE_STATUSES) {
      countMap[status] = allQuotes.filter((q) => q.status === status).length;
    }
  }
  const allCount = allQuotes
    ? allQuotes.filter((q) => q.status !== "revised").length
    : 0;

  // Filter by active tab (exclude "revised" from all tabs — backend hides them but defensive client filter)
  const tabFiltered = allQuotes
    ? activeTab === "all"
      ? allQuotes.filter((q) => q.status !== "revised")
      : allQuotes.filter((q) => q.status === activeTab)
    : [];

  // Filter by search query (client-side)
  const searchFiltered = debouncedSearch
    ? tabFiltered.filter((q) => {
        const quoteRef = `QT-${q.id.slice(0, 6).toUpperCase()}`;
        const jobDesc =
          jobsMap[q.job_id]?.description?.toLowerCase() ?? "";
        const clientName =
          jobsMap[q.job_id]?.client_name?.toLowerCase() ?? "";
        const query = debouncedSearch.toLowerCase();
        return (
          quoteRef.toLowerCase().includes(query) ||
          jobDesc.includes(query) ||
          clientName.includes(query)
        );
      })
    : tabFiltered;

  // Client-side sort
  const sortedQuotes = sortQuotes(searchFiltered, sortCol, sortDir);

  // Pagination
  const startIdx = (page - 1) * PAGE_SIZE;
  const pagedQuotes = sortedQuotes.slice(startIdx, startIdx + PAGE_SIZE);

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

  const getTabCount = (value: string): number | undefined => {
    if (!allQuotes) return undefined;
    if (value === "all") return allCount;
    return countMap[value];
  };

  return (
    <div className="space-y-4">
      {/* Header row: page title + search bar */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-gray-900">Quotes</h1>
        <div className="relative w-72">
          <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 pointer-events-none" />
          <Input
            className="pl-8"
            placeholder="Search quotes..."
            value={searchInput}
            onChange={handleSearchChange}
          />
        </div>
      </div>

      {/* Status tab bar */}
      <div className="flex items-center border-b border-gray-200">
        {QUOTE_STATUS_TABS.map((tab) => {
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
              {count !== undefined && (
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
        ) : pagedQuotes.length === 0 ? (
          <EmptyState
            title={
              activeTab === "all"
                ? "No quotes yet"
                : `No ${activeTab} quotes`
            }
            message={
              activeTab === "all"
                ? "Quotes are created from job detail pages. Open a job in Quote status to get started."
                : `There are no quotes with ${activeTab} status.`
            }
          />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none"
                  onClick={() => handleSortChange("id")}
                >
                  Quote #
                  <SortIcon col="id" />
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Job
                </TableHead>
                <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Client
                </TableHead>
                <TableHead
                  className="text-xs font-semibold text-gray-500 uppercase tracking-wide cursor-pointer select-none text-right"
                  onClick={() => handleSortChange("total")}
                >
                  Total
                  <SortIcon col="total" />
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
                  onClick={() => handleSortChange("created_at")}
                >
                  Date
                  <SortIcon col="created_at" />
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pagedQuotes.map((quote) => (
                <TableRow
                  key={quote.id}
                  className="cursor-pointer hover:bg-gray-50"
                  onClick={() => router.push(`/quotes/${quote.id}`)}
                >
                  <TableCell className="py-3 px-4 font-mono text-sm text-gray-900">
                    {`QT-${quote.id.slice(0, 6).toUpperCase()}`}
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-[160px]">
                    {jobsMap[quote.job_id]?.description ?? "—"}
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-700">
                    {jobsMap[quote.job_id]?.client_name ?? "—"}
                  </TableCell>
                  <TableCell className="py-3 px-4 font-mono text-sm text-gray-900 text-right">
                    {`$${Number(quote.total).toLocaleString("en-US", {
                      minimumFractionDigits: 2,
                      maximumFractionDigits: 2,
                    })}`}
                  </TableCell>
                  <TableCell className="py-3 px-4">
                    <StatusBadge status={quote.status} size="sm" />
                  </TableCell>
                  <TableCell className="py-3 px-4 text-sm text-gray-500">
                    {new Date(quote.created_at).toLocaleDateString()}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </div>

      {/* Pagination */}
      <div className="flex items-center justify-between">
        <span className="text-sm text-gray-500">Showing page {page}</span>
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
            disabled={pagedQuotes.length < PAGE_SIZE}
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
          <Skeleton className="h-4 w-20" />
          <Skeleton className="h-4 w-16" />
          <Skeleton className="h-4 w-16" />
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
