"use client";

import { Suspense } from "react";
import Link from "next/link";
import { Search, Bot } from "lucide-react";
import { Input } from "@/components/ui/input";
import { ListPagination } from "@/components/shared/list-pagination";
import { ListStatusTabs } from "@/components/shared/list-tabs";
import {
  DEFAULT_PAGE_SIZE,
  useListTableFilters,
} from "@/hooks/use-list-table-filters";
import { QuotesListBody } from "./_components/quotes-list-body";
import { useQuotesListData } from "./_hooks/use-quotes-list-data";
import { DEFAULT_SORT_COLUMN, QUOTE_STATUS_TABS } from "./_lib/quote-list";

// Wrapped in Suspense because useSearchParams() requires a boundary in Next.js.
export default function QuotesPage() {
  return (
    <Suspense>
      <QuotesPageContent />
    </Suspense>
  );
}

function QuotesPageContent() {
  const filters = useListTableFilters({
    basePath: "/quotes",
    defaultSortColumn: DEFAULT_SORT_COLUMN,
  });

  const { isLoading, jobsById, visibleQuotes, totalCount, getTabCount } =
    useQuotesListData({
      activeTab: filters.activeTab,
      page: filters.page,
      search: filters.searchQuery,
      sortColumn: filters.sortColumn,
      sortDirection: filters.sortDirection,
    });

  const totalPages = Math.max(1, Math.ceil(totalCount / DEFAULT_PAGE_SIZE));

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-xl font-semibold text-gray-900">Quotes</h1>
        <div className="flex items-center gap-3">
          <div className="relative w-72">
            <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 pointer-events-none" />
            <Input
              className="pl-8"
              placeholder="Search quotes..."
              value={filters.searchInput}
              onChange={filters.onSearchChange}
            />
          </div>
          <Link
            href="/quotes/new-project"
            className="inline-flex h-9 flex-shrink-0 items-center gap-1.5 rounded-lg bg-brand px-3 text-sm font-medium text-brand-foreground transition-colors hover:bg-brand/90"
          >
            <Bot className="h-4 w-4" />
            New Project Quote
          </Link>
        </div>
      </div>

      <ListStatusTabs
        tabs={QUOTE_STATUS_TABS}
        activeTab={filters.activeTab}
        onTabChange={filters.onTabChange}
        getTabCount={getTabCount}
      />

      <QuotesListBody
        quotes={visibleQuotes}
        isLoading={isLoading}
        jobsById={jobsById}
        activeTab={filters.activeTab}
        sortColumn={filters.sortColumn}
        sortDirection={filters.sortDirection}
        onSortChange={filters.onSortChange}
      />

      <ListPagination
        page={filters.page}
        totalPages={totalPages}
        hasNextPage={filters.page < totalPages}
        onPageChange={filters.onPageChange}
      />
    </div>
  );
}
