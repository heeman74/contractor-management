import React from "react";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { apiGet } from "@/lib/api-client";
import {
  fetchCompanyFinancials,
  fetchProjectFinancials,
  fetchProjectMarginTrend,
} from "@/features/finance/api";
import {
  useCompanyFinancials,
  useProjectFinancials,
  useProjectMarginTrend,
  useProjectProfitabilityFinding,
} from "../hooks";
import { formatFindingDate } from "../financials-format";
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
/** fetchProjectProfitabilityFinding is deliberately left REAL above: the finding
 *  tests below mock the HTTP layer instead, so one test covers the gate, the
 *  request path and the snake_case mapping together. */
jest.mock("@/lib/api-client", () => ({
  ...jest.requireActual("@/lib/api-client"),
  apiGet: jest.fn(),
}));

const mockUsePermissions = usePermissions as jest.Mock;
const mockFetchCompany = fetchCompanyFinancials as jest.Mock;
const mockFetchProject = fetchProjectFinancials as jest.Mock;
const mockFetchTrend = fetchProjectMarginTrend as jest.Mock;
const mockApiGet = apiGet as jest.Mock;

const PROJECT_ID = "11111111-1111-1111-1111-111111111111";
const FINDING_PATH = `/api/v1/projects/${PROJECT_ID}/financials/finding`;

const FINDING_RESPONSE = {
  id: "22222222-2222-2222-2222-222222222222",
  project_id: PROJECT_ID,
  severity: "critical",
  narrative: "Margin fell 12 points after the framing scope overran its budget.",
  corrective_action: "Re-price the remaining framing work before the next invoice.",
  revenue_basis: "quoted",
  labor_included: true,
  found_on: "2026-07-22",
  last_confirmed_on: "2026-07-29",
};

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

/**
 * These assert on the HTTP layer, not on a render flag, because the SC2 keystone
 * is that a denied user puts NOTHING money-adjacent on the wire. Deleting
 * `enabled` from the hook makes the zero-request test fail — which is the only
 * thing that stops the Playwright zero-request assertion from passing for the
 * wrong reason.
 */
describe("useProjectProfitabilityFinding", () => {
  beforeEach(() => {
    mockUsePermissions.mockReset();
    mockApiGet.mockReset().mockResolvedValue(FINDING_RESPONSE);
  });

  test("issues exactly one request to the finding path and maps it to camelCase", async () => {
    grantPermission(true);
    const { wrapper } = createWrapper();

    const { result } = renderHook(
      () => useProjectProfitabilityFinding(PROJECT_ID),
      { wrapper }
    );
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(mockApiGet).toHaveBeenCalledTimes(1);
    expect(mockApiGet).toHaveBeenCalledWith(FINDING_PATH);
    expect(result.current.data).toEqual({
      id: FINDING_RESPONSE.id,
      projectId: PROJECT_ID,
      severity: "critical",
      narrative: FINDING_RESPONSE.narrative,
      correctiveAction: FINDING_RESPONSE.corrective_action,
      revenueBasis: "quoted",
      laborIncluded: true,
      foundOn: "2026-07-22",
      lastConfirmedOn: "2026-07-29",
    });
  });

  test("issues zero finding requests when the user lacks finance.view", async () => {
    grantPermission(false);
    const { wrapper } = createWrapper();

    const { result } = renderHook(
      () => useProjectProfitabilityFinding(PROJECT_ID),
      { wrapper }
    );

    expect(mockApiGet).not.toHaveBeenCalled();
    expect(result.current.fetchStatus).toBe("idle");
  });

  test("resolves a null body to no finding rather than an error", async () => {
    grantPermission(true);
    mockApiGet.mockResolvedValue(null);
    const { wrapper } = createWrapper();

    const { result } = renderHook(
      () => useProjectProfitabilityFinding(PROJECT_ID),
      { wrapper }
    );
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(result.current.data).toBeNull();
    expect(result.current.isError).toBe(false);
  });

  /** An unknown band would index the card's severity-chip map with `undefined`
   *  and crash the whole drill-down at render. Validating it at the boundary
   *  turns a malformed payload into this one card's error state instead. */
  test("rejects an unknown severity band instead of mapping it through", async () => {
    grantPermission(true);
    mockApiGet.mockResolvedValue({ ...FINDING_RESPONSE, severity: "catastrophic" });
    const { wrapper } = createWrapper();

    const { result } = renderHook(
      () => useProjectProfitabilityFinding(PROJECT_ID),
      { wrapper }
    );
    await waitFor(() => expect(result.current.isError).toBe(true));

    expect((result.current.error as Error).message).toMatch(/severity/i);
  });
});

describe("formatFindingDate", () => {
  test("renders a date-only string in the locked Jul 29, 2026 shape", () => {
    expect(formatFindingDate("2026-07-29")).toBe("Jul 29, 2026");
  });

  test("never zero-pads the day", () => {
    expect(formatFindingDate("2026-01-01")).toBe("Jan 1, 2026");
  });

  test("returns an unparseable string unchanged rather than a wrong date", () => {
    expect(formatFindingDate("not-a-date")).toBe("not-a-date");
  });
});
