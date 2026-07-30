import React from "react";
import { render, screen, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { apiGet } from "@/lib/api-client";
import { FinanceGate } from "@/features/finance/components/FinanceGate";
import { useQuoteVariance } from "@/features/finance/hooks";

jest.mock("@/lib/hooks/usePermissions", () => ({ usePermissions: jest.fn() }));
jest.mock("@/lib/api-client", () => ({
  ...jest.requireActual("@/lib/api-client"),
  apiGet: jest.fn(),
}));

const mockUsePermissions = usePermissions as jest.Mock;
const mockApiGet = apiGet as jest.Mock;

const CHILD_TEXT = "Quoted vs Actual card contents";

function permissionState(can: (key: string) => boolean, isLoading = false) {
  mockUsePermissions.mockReturnValue({
    can,
    permissions: new Set<string>(),
    isLoading,
  });
}

function renderGate(fallback?: React.ReactNode) {
  const props = fallback === undefined ? {} : { fallback };
  return render(
    <FinanceGate {...props}>
      <p>{CHILD_TEXT}</p>
    </FinanceGate>
  );
}

describe("FinanceGate fallback", () => {
  beforeEach(() => {
    mockUsePermissions.mockReset();
  });

  it("omitted prop + loading: renders the shipped 256px pulse", () => {
    permissionState(() => false, true);

    const { container } = renderGate(undefined);

    expect(container.querySelector(".h-64.animate-pulse")).toBeInTheDocument();
    expect(screen.queryByText(CHILD_TEXT)).not.toBeInTheDocument();
  });

  it("omitted prop + denied: renders the shipped yellow deny panel", () => {
    permissionState(() => false);

    renderGate(undefined);

    expect(screen.getByTestId("financials-deny-panel")).toBeInTheDocument();
    expect(screen.queryByText(CHILD_TEXT)).not.toBeInTheDocument();
  });

  it("fallback={null} + loading: renders nothing", () => {
    permissionState(() => false, true);

    const { container } = renderGate(null);

    expect(container).toBeEmptyDOMElement();
  });

  it("fallback={null} + denied: renders nothing and no deny panel", () => {
    permissionState(() => false);

    const { container } = renderGate(null);

    expect(container).toBeEmptyDOMElement();
    expect(screen.queryByTestId("financials-deny-panel")).not.toBeInTheDocument();
  });

  it("permission granted: renders children in both the omitted and fallback={null} cases", () => {
    permissionState(() => true);
    const { unmount } = renderGate(undefined);
    expect(screen.getByText(CHILD_TEXT)).toBeInTheDocument();
    unmount();

    renderGate(null);
    expect(screen.getByText(CHILD_TEXT)).toBeInTheDocument();
  });
});

// ---------------------------------------------------------------------------

const QUOTE_ID = "33333333-3333-3333-3333-333333333333";
const VARIANCE_PATH = `/api/v1/quotes/${QUOTE_ID}/variance`;

const VARIANCE_RESPONSE = {
  quoted: "12400.00",
  actual: "13640.00",
  variance: "1240.00",
  variance_percent: "10.0",
  labor_included: true,
  scope_anchored: false,
  trades: [
    {
      label: "Plumbing",
      quoted: "6000.00",
      actual: "6800.00",
      variance: "800.00",
      variance_percent: "13.3",
    },
  ],
};

function createQueryWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
  return wrapper;
}

/**
 * `useQuoteVariance` is the fetch-side half of the Trap 8 double lock. These
 * tests drive it directly, without `FinanceGate`, which is what proves `enabled`
 * holds on its own rather than merely looking correct behind the render gate.
 */
describe("useQuoteVariance", () => {
  beforeEach(() => {
    mockUsePermissions.mockReset();
    mockApiGet.mockReset().mockResolvedValue(VARIANCE_RESPONSE);
  });

  function grantPermission(granted: boolean) {
    mockUsePermissions.mockReturnValue({
      can: () => granted,
      permissions: new Set<string>(),
      isLoading: false,
    });
  }

  it("issues exactly one GET to the variance path and maps the response to camelCase", async () => {
    grantPermission(true);
    const { result } = renderHook(() => useQuoteVariance(QUOTE_ID, true), {
      wrapper: createQueryWrapper(),
    });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(mockApiGet).toHaveBeenCalledTimes(1);
    expect(mockApiGet).toHaveBeenCalledWith(VARIANCE_PATH);
    expect(result.current.data).toEqual({
      quoted: "12400.00",
      actual: "13640.00",
      variance: "1240.00",
      variancePercent: "10.0",
      laborIncluded: true,
      scopeAnchored: false,
      trades: [
        {
          label: "Plumbing",
          quoted: "6000.00",
          actual: "6800.00",
          variance: "800.00",
          variancePercent: "13.3",
        },
      ],
    });
  });

  it("is disabled and issues zero requests when the viewer lacks finance.view", () => {
    grantPermission(false);
    const { result } = renderHook(() => useQuoteVariance(QUOTE_ID, true), {
      wrapper: createQueryWrapper(),
    });

    expect(mockApiGet).not.toHaveBeenCalled();
    expect(result.current.fetchStatus).toBe("idle");
  });

  it("is disabled and issues zero requests when the quote is not approved", () => {
    grantPermission(true);
    const { result } = renderHook(() => useQuoteVariance(QUOTE_ID, false), {
      wrapper: createQueryWrapper(),
    });

    expect(mockApiGet).not.toHaveBeenCalled();
    expect(result.current.fetchStatus).toBe("idle");
  });

  it("is enabled and fires exactly one request when both finance.view and approved hold", async () => {
    grantPermission(true);
    renderHook(() => useQuoteVariance(QUOTE_ID, true), {
      wrapper: createQueryWrapper(),
    });

    await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(1));
  });
});
