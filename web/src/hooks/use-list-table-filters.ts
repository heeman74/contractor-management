import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

export type SortDirection = "asc" | "desc";

export const DEFAULT_PAGE_SIZE = 25;
export const SEARCH_DEBOUNCE_MS = 300;
export const ALL_TAB = "all";

interface UseListTableFiltersArgs<TSortColumn extends string> {
  basePath: string;
  defaultSortColumn: TSortColumn;
  defaultSortDirection?: SortDirection;
}

export interface ListTableFilters<TSortColumn extends string> {
  activeTab: string;
  page: number;
  searchQuery: string;
  sortColumn: TSortColumn;
  sortDirection: SortDirection;
  searchInput: string;
  onSearchChange: (event: React.ChangeEvent<HTMLInputElement>) => void;
  onTabChange: (tab: string) => void;
  onSortChange: (column: TSortColumn) => void;
  onPageChange: (page: number) => void;
}

/**
 * URL-driven filter/sort/search/pagination state for list table pages.
 * The URL query string is the single source of truth; the debounced search
 * input is the only local state, kept in sync with the `q` param.
 */
export function useListTableFilters<TSortColumn extends string>({
  basePath,
  defaultSortColumn,
  defaultSortDirection = "desc",
}: UseListTableFiltersArgs<TSortColumn>): ListTableFilters<TSortColumn> {
  const router = useRouter();
  const searchParams = useSearchParams();

  const activeTab = searchParams.get("tab") ?? ALL_TAB;
  const page = parseInt(searchParams.get("page") ?? "1", 10);
  const searchQuery = searchParams.get("q") ?? "";
  const sortColumn = (searchParams.get("sort") ??
    defaultSortColumn) as TSortColumn;
  const sortDirection = (searchParams.get("dir") ??
    defaultSortDirection) as SortDirection;

  const [searchInput, setSearchInput] = useState(searchQuery);
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    setSearchInput(searchQuery);
  }, [searchQuery]);

  const pushParams = useCallback(
    (mutate: (params: URLSearchParams) => void) => {
      const params = new URLSearchParams(searchParams.toString());
      mutate(params);
      router.push(`${basePath}?${params.toString()}`);
    },
    [basePath, router, searchParams]
  );

  const onSearchChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const value = event.target.value;
      setSearchInput(value);
      if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = setTimeout(() => {
        const params = new URLSearchParams(searchParams.toString());
        if (value) params.set("q", value);
        else params.delete("q");
        params.set("page", "1");
        router.replace(`${basePath}?${params.toString()}`);
      }, SEARCH_DEBOUNCE_MS);
    },
    [basePath, router, searchParams]
  );

  const onTabChange = useCallback(
    (tab: string) => {
      pushParams((params) => {
        params.set("tab", tab);
        params.set("page", "1");
      });
    },
    [pushParams]
  );

  const onSortChange = useCallback(
    (column: TSortColumn) => {
      pushParams((params) => {
        if (sortColumn === column) {
          params.set("dir", sortDirection === "asc" ? "desc" : "asc");
        } else {
          params.set("sort", column);
          params.set("dir", "desc");
        }
        params.set("page", "1");
      });
    },
    [pushParams, sortColumn, sortDirection]
  );

  const onPageChange = useCallback(
    (nextPage: number) => {
      pushParams((params) => params.set("page", String(nextPage)));
    },
    [pushParams]
  );

  return {
    activeTab,
    page,
    searchQuery,
    sortColumn,
    sortDirection,
    searchInput,
    onSearchChange,
    onTabChange,
    onSortChange,
    onPageChange,
  };
}
