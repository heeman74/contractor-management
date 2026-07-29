import React from "react";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { usePermissions } from "@/lib/hooks/usePermissions";
import {
  fetchCompanyFinancials,
  fetchProjectFinancials,
  fetchProjectMarginTrend,
} from "@/features/finance/api";
import {
  useCompanyFinancials,
  useProjectFinancials,
  useProjectMarginTrend,
} from "../hooks";
import type { TrendWindow } from "../types";

/**
 * The grep-able `enabled: can(FINANCE_VIEW_PERMISSION)` proves the prop is
 * spelled right; only these render tests prove it WORKS. A denied or
 * still-loading visit must issue zero financial requests — that is what makes
 * the Playwright "no /api/v1/financials/* requests" assertion test the gate
 * rather than an unhydrated store. Do not relax these into render-only
 * assertions.
 */

jest.mock("@/lib/hooks/usePermissions", () => ({ usePermissions: jest.fn() }));
jest.mock("@/features/finance/api", () => ({
  ...jest.requireActual("@/features/finance/api"),
  fetchCompanyFinancials: jest.fn(),
  fetchProjectFinancials: jest.fn(),
  fetchProjectMarginTrend: jest.fn(),
}));

const mockUsePermissions = usePermissions as jest.Mock;
const mockFetchCompany = fetchCompanyFinancials as jest.Mock;
const mockFetchProject = fetchProjectFinancials as jest.Mock;
const mockFetchTrend = fetchProjectMarginTrend as jest.Mock;

const PROJECT_ID = "11111111-1111-1111-1111-111111111111";

type TrendWindowProps = { window: TrendWindow };

function grantPermission(granted: boolean, isLoading = false) {
  mockUsePermissions.mockReturnValue({
    can: () => granted,
    permissions: new Set<string>(),
    isLoading,
  });
}

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
  return { queryClient, wrapper };
}

function useAllFinancialQueries() {
  return {
    company: useCompanyFinancials(),
    project: useProjectFinancials(PROJECT_ID),
    trend: useProjectMarginTrend(PROJECT_ID, "12m"),
  };
}

describe("financial dashboard hooks", () => {
  beforeEach(() => {
    mockUsePermissions.mockReset();
    mockFetchCompany.mockReset().mockResolvedValue({});
    mockFetchProject.mockReset().mockResolvedValue({});
    mockFetchTrend.mockReset().mockResolvedValue({});
  });

  test("issues zero financial requests when the user lacks finance.view", async () => {
    grantPermission(false);
    const { wrapper } = createWrapper();

    const { result } = renderHook(() => useAllFinancialQueries(), { wrapper });

    expect(mockFetchCompany).not.toHaveBeenCalled();
    expect(mockFetchProject).not.toHaveBeenCalled();
    expect(mockFetchTrend).not.toHaveBeenCalled();
    expect(result.current.company.fetchStatus).toBe("idle");
    expect(result.current.project.fetchStatus).toBe("idle");
    expect(result.current.trend.fetchStatus).toBe("idle");
  });

  test("issues zero financial requests while permissions are still loading", async () => {
    grantPermission(false, true);
    const { wrapper } = createWrapper();

    renderHook(() => useAllFinancialQueries(), { wrapper });

    expect(mockFetchCompany).not.toHaveBeenCalled();
    expect(mockFetchProject).not.toHaveBeenCalled();
    expect(mockFetchTrend).not.toHaveBeenCalled();
  });

  test("fetches each financial endpoint exactly once when permitted", async () => {
    grantPermission(true);
    const { wrapper } = createWrapper();

    const { result } = renderHook(() => useAllFinancialQueries(), { wrapper });

    await waitFor(() => expect(result.current.company.isSuccess).toBe(true));
    await waitFor(() => expect(result.current.project.isSuccess).toBe(true));
    await waitFor(() => expect(result.current.trend.isSuccess).toBe(true));

    expect(mockFetchCompany).toHaveBeenCalledTimes(1);
    expect(mockFetchProject).toHaveBeenCalledTimes(1);
    expect(mockFetchProject).toHaveBeenCalledWith(PROJECT_ID);
    expect(mockFetchTrend).toHaveBeenCalledTimes(1);
    expect(mockFetchTrend).toHaveBeenCalledWith(PROJECT_ID, "12m");
  });

  test("keys the trend by window so a window switch refetches only the trend", async () => {
    grantPermission(true);
    const { queryClient, wrapper } = createWrapper();

    const initialProps: TrendWindowProps = { window: "3m" };
    const { result, rerender } = renderHook(
      ({ window }: TrendWindowProps) => useProjectMarginTrend(PROJECT_ID, window),
      { wrapper, initialProps }
    );
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    rerender({ window: "12m" });
    await waitFor(() => expect(mockFetchTrend).toHaveBeenCalledTimes(2));

    expect(mockFetchTrend).toHaveBeenNthCalledWith(1, PROJECT_ID, "3m");
    expect(mockFetchTrend).toHaveBeenNthCalledWith(2, PROJECT_ID, "12m");

    const trendKeys = queryClient
      .getQueryCache()
      .getAll()
      .map((query) => query.queryKey);
    expect(trendKeys).toEqual([
      ["cost-entries", "financials", "trend", PROJECT_ID, "3m"],
      ["cost-entries", "financials", "trend", PROJECT_ID, "12m"],
    ]);
  });

  test("keys every financial query under the cost-entries invalidation prefix", async () => {
    grantPermission(true);
    const { queryClient, wrapper } = createWrapper();

    const { result } = renderHook(() => useAllFinancialQueries(), { wrapper });
    await waitFor(() => expect(result.current.company.isSuccess).toBe(true));

    const keys = queryClient
      .getQueryCache()
      .getAll()
      .map((query) => query.queryKey);
    expect(keys).toHaveLength(3);
    for (const key of keys) {
      expect(key.slice(0, 2)).toEqual(["cost-entries", "financials"]);
    }
  });
});
