import React from "react";
import { render, screen } from "@testing-library/react";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { FinanceGate } from "@/features/finance/components/FinanceGate";

jest.mock("@/lib/hooks/usePermissions", () => ({ usePermissions: jest.fn() }));

const mockUsePermissions = usePermissions as jest.Mock;

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
