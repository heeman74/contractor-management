"use client";

import { Suspense } from "react";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { ListPagination } from "@/components/shared/list-pagination";
import { ListStatusTabs } from "@/components/shared/list-tabs";
import {
  DEFAULT_PAGE_SIZE,
  useListTableFilters,
} from "@/hooks/use-list-table-filters";
import { InvoicesListBody } from "./_components/invoices-list-body";
import { useInvoicesListData } from "./_hooks/use-invoices-list-data";
import { DEFAULT_SORT_COLUMN, INVOICE_STATUS_TABS } from "./_lib/invoice-list";

// Wrapped in Suspense because useSearchParams() requires a boundary in Next.js.
export default function InvoicesPage() {
  return (
    <Suspense>
      <InvoicesPageContent />
    </Suspense>
  );
}

function InvoicesPageContent() {
  const filters = useListTableFilters({
    basePath: "/invoices",
    defaultSortColumn: DEFAULT_SORT_COLUMN,
  });

  const { isLoading, isLoaded, jobsById, visibleInvoices, totalCount, getTabCount } =
    useInvoicesListData({
      activeTab: filters.activeTab,
      page: filters.page,
      search: filters.searchQuery,
      sortColumn: filters.sortColumn,
      sortDirection: filters.sortDirection,
    });

  const totalPages = Math.max(1, Math.ceil(totalCount / DEFAULT_PAGE_SIZE));

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-gray-900">Invoices</h1>
        <div className="relative w-72">
          <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 pointer-events-none" />
          <Input
            className="pl-8"
            placeholder="Search invoices..."
            value={filters.searchInput}
            onChange={filters.onSearchChange}
          />
        </div>
      </div>

      <ListStatusTabs
        tabs={INVOICE_STATUS_TABS}
        activeTab={filters.activeTab}
        onTabChange={filters.onTabChange}
        getTabCount={(value) => (isLoaded ? getTabCount(value) : undefined)}
      />

      <InvoicesListBody
        invoices={visibleInvoices}
        isLoading={isLoading}
        jobsById={jobsById}
        activeTab={filters.activeTab}
        hasSearch={!!filters.searchQuery}
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
