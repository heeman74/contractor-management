import React from "react";
import { render, screen, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { apiGet } from "@/lib/api-client";
import { FinanceGate } from "@/features/finance/components/FinanceGate";
import { useQuoteVariance } from "@/features/finance/hooks";
import { QuoteVarianceSection } from "../[id]/_components/quote-variance-section";
import { QuoteVarianceCard } from "../[id]/_components/quote-variance-card";

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

// ---------------------------------------------------------------------------

/** The exact composition `quotes/[id]/page.tsx` mounts. This is the layering
 *  under test: FinanceGate short-circuits before QuoteVarianceSection (the
 *  hook's owner) ever mounts, so an unauthorized or not-yet-resolved visit
 *  proves zero requests rather than merely a hidden card. */
function renderVarianceGate(isApproved: boolean) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <FinanceGate fallback={null}>
        <QuoteVarianceSection quoteId={QUOTE_ID} isApproved={isApproved} />
      </FinanceGate>
    </QueryClientProvider>
  );
}

describe("quote variance gate", () => {
  beforeEach(() => {
    mockUsePermissions.mockReset();
    mockApiGet.mockReset().mockResolvedValue(VARIANCE_RESPONSE);
  });

  it("state 37: renders nothing and issues zero requests while permissions load", () => {
    mockUsePermissions.mockReturnValue({
      can: () => false,
      permissions: new Set<string>(),
      isLoading: true,
    });

    const { container } = renderVarianceGate(true);

    expect(container).toBeEmptyDOMElement();
    expect(mockApiGet).not.toHaveBeenCalled();
  });

  it("state 38: renders no card and no deny panel for a quotes.view-only viewer, zero requests", () => {
    mockUsePermissions.mockReturnValue({
      can: () => false,
      permissions: new Set<string>(),
      isLoading: false,
    });

    renderVarianceGate(true);

    expect(screen.queryByTestId("quote-variance")).not.toBeInTheDocument();
    expect(screen.queryByTestId("financials-deny-panel")).not.toBeInTheDocument();
    expect(mockApiGet).not.toHaveBeenCalled();
  });

  it("state 39: renders no card and issues zero requests for a non-approved quote", () => {
    mockUsePermissions.mockReturnValue({
      can: () => true,
      permissions: new Set<string>(),
      isLoading: false,
    });

    renderVarianceGate(false);

    expect(screen.queryByTestId("quote-variance")).not.toBeInTheDocument();
    expect(mockApiGet).not.toHaveBeenCalled();
  });

  it("renders the card for an approved quote when finance.view is granted", async () => {
    mockUsePermissions.mockReturnValue({
      can: () => true,
      permissions: new Set<string>(),
      isLoading: false,
    });

    renderVarianceGate(true);

    expect(await screen.findByTestId("quote-variance")).toBeInTheDocument();
    expect(mockApiGet).toHaveBeenCalledWith(VARIANCE_PATH);
  });
});

// ---------------------------------------------------------------------------

const NOT_COMPARABLE_VARIANCE = {
  quoted: null,
  actual: null,
  variance: null,
  variancePercent: null,
  laborIncluded: false,
  scopeAnchored: false,
  trades: [],
};

const UNDER_QUOTED_VARIANCE = {
  quoted: "10000.00",
  actual: "9200.00",
  variance: "-800.00",
  variancePercent: "-8.0",
  laborIncluded: false,
  scopeAnchored: false,
  trades: [],
};

const OVER_QUOTED_VARIANCE = {
  quoted: "12400.00",
  actual: "13640.00",
  variance: "1240.00",
  variancePercent: "10.0",
  laborIncluded: true,
  scopeAnchored: false,
  trades: [],
};

const SCOPE_ANCHORED_VARIANCE = {
  ...UNDER_QUOTED_VARIANCE,
  scopeAnchored: true,
};

const PROJECT_LEVEL_VARIANCE = {
  quoted: "20000.00",
  actual: "18000.00",
  variance: "-2000.00",
  variancePercent: "-10.0",
  laborIncluded: false,
  scopeAnchored: false,
  trades: [
    {
      label: "Plumbing",
      quoted: "8000.00",
      actual: "7000.00",
      variance: "-1000.00",
      variancePercent: "-12.5",
    },
    {
      label: "Electrical",
      quoted: "6000.00",
      actual: null,
      variance: null,
      variancePercent: null,
    },
  ],
};

describe("quote variance card", () => {
  it("renders a skeleton while loading", () => {
    render(<QuoteVarianceCard variance={undefined} isLoading isError={false} />);

    expect(screen.getByTestId("quote-variance-skeleton")).toBeInTheDocument();
  });

  it("renders the in-card error line on a query error", () => {
    render(
      <QuoteVarianceCard variance={undefined} isLoading={false} isError />
    );

    expect(screen.getByTestId("quote-variance-error")).toHaveTextContent(
      "Couldn't load quoted vs actual. Refresh to try again."
    );
  });

  it("renders no card at all when there is no result and nothing is loading or erroring", () => {
    const { container } = render(
      <QuoteVarianceCard variance={undefined} isLoading={false} isError={false} />
    );

    expect(container).toBeEmptyDOMElement();
  });

  it("renders the Not comparable yet empty state for a null quoted/actual", () => {
    render(
      <QuoteVarianceCard
        variance={NOT_COMPARABLE_VARIANCE}
        isLoading={false}
        isError={false}
      />
    );

    expect(screen.getByTestId("quote-variance-empty")).toHaveTextContent(
      "Not comparable yet"
    );
    expect(screen.getByTestId("quote-variance-empty")).toHaveTextContent(
      "Quoted vs actual appears once the work from this quote has been invoiced."
    );
  });

  it("renders red-800 on an over-quoted (positive) variance with the above interpretation", () => {
    render(
      <QuoteVarianceCard
        variance={OVER_QUOTED_VARIANCE}
        isLoading={false}
        isError={false}
      />
    );

    const figure = screen.getByTestId("quote-variance-figure");
    expect(figure.className).toContain("text-red-800");
    expect(screen.getByTestId("quote-variance-interpretation")).toHaveTextContent(
      /above this quote's pre-tax price\.$/
    );
  });

  it("renders gray-900 on an under-quoted (negative) variance with the below interpretation, no green", () => {
    render(
      <QuoteVarianceCard
        variance={UNDER_QUOTED_VARIANCE}
        isLoading={false}
        isError={false}
      />
    );

    const figure = screen.getByTestId("quote-variance-figure");
    expect(figure.className).toContain("text-gray-900");
    expect(figure.className).not.toMatch(/text-green/);
    expect(screen.getByTestId("quote-variance-interpretation")).toHaveTextContent(
      /below this quote's pre-tax price\.$/
    );
  });

  it("renders the scope-labor caption for a trade-scope-anchored quote", () => {
    render(
      <QuoteVarianceCard
        variance={SCOPE_ANCHORED_VARIANCE}
        isLoading={false}
        isError={false}
      />
    );

    expect(screen.getByTestId("scope-labor-note")).toHaveTextContent(
      "Scope spend excludes labor — labor is tracked at job level."
    );
  });

  it("renders the unburdened-labor caption whenever the actual includes derived labor", () => {
    render(
      <QuoteVarianceCard
        variance={OVER_QUOTED_VARIANCE}
        isLoading={false}
        isError={false}
      />
    );

    expect(screen.getByText(/Unburdened labor/)).toBeInTheDocument();
  });

  it("renders one row per trade plus a Project total row, and Not yet invoiced for an uninvoiced trade", () => {
    render(
      <QuoteVarianceCard
        variance={PROJECT_LEVEL_VARIANCE}
        isLoading={false}
        isError={false}
      />
    );

    expect(screen.getByText("Plumbing")).toBeInTheDocument();
    expect(screen.getByText("Electrical")).toBeInTheDocument();
    expect(screen.getByText("Project total")).toBeInTheDocument();
    expect(screen.getByText("Not yet invoiced")).toBeInTheDocument();
    expect(screen.getByTestId("quote-variance-figure")).toBeInTheDocument();
  });
});
