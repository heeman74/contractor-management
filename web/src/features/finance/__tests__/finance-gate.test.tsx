import React from "react";
import { render, screen } from "@testing-library/react";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { FinancialsSkeleton } from "@/app/(dashboard)/financials/_components/financials-skeleton";
import { FINANCE_DENY_MESSAGE, FinanceGate } from "../components/FinanceGate";
import { FINANCE_VIEW_PERMISSION } from "../types";

jest.mock("@/lib/hooks/usePermissions", () => ({ usePermissions: jest.fn() }));

const mockUsePermissions = usePermissions as jest.Mock;

const CHILD_TEXT = "Portfolio margin and budget health.";

function permissionState(can: (key: string) => boolean, isLoading = false) {
  mockUsePermissions.mockReturnValue({
    can,
    permissions: new Set<string>(),
    isLoading,
  });
}

function renderGate() {
  return render(
    <FinanceGate>
      <p>{CHILD_TEXT}</p>
    </FinanceGate>
  );
}

describe("FinanceGate", () => {
  beforeEach(() => {
    mockUsePermissions.mockReset();
  });

  it("state 1: renders the loading pulse and no child while permissions resolve", () => {
    permissionState(() => false, true);

    const { container } = renderGate();

    expect(container.querySelector(".animate-pulse")).toBeInTheDocument();
    expect(screen.queryByText(CHILD_TEXT)).not.toBeInTheDocument();
    expect(screen.queryByTestId("financials-deny-panel")).not.toBeInTheDocument();
  });

  it("state 2: renders the deny panel and no child without the permission", () => {
    permissionState(() => false);

    renderGate();

    const panel = screen.getByTestId("financials-deny-panel");
    expect(panel).toHaveTextContent("You do not have permission to view financials.");
    expect(FINANCE_DENY_MESSAGE).toBe("You do not have permission to view financials.");
    expect(screen.queryByText(CHILD_TEXT)).not.toBeInTheDocument();
  });

  it("renders children unchanged and no deny panel with the permission", () => {
    permissionState(() => true);

    renderGate();

    expect(screen.getByText(CHILD_TEXT)).toBeInTheDocument();
    expect(screen.queryByTestId("financials-deny-panel")).not.toBeInTheDocument();
  });

  it("fails closed on exactly the finance.view key the hooks gate their fetches on", () => {
    const can = jest.fn(() => true);
    permissionState(can);

    renderGate();

    expect(can).toHaveBeenCalledWith(FINANCE_VIEW_PERMISSION);
  });
});

describe("FinancialsSkeleton", () => {
  it("renders the company layout: 3 tiles, 2 chart cards and a table block", () => {
    render(<FinancialsSkeleton variant="company" />);

    expect(screen.getByTestId("financials-skeleton")).toBeInTheDocument();
    expect(screen.getAllByTestId("financials-skeleton-tile")).toHaveLength(3);
    expect(screen.getAllByTestId("financials-skeleton-chart-card")).toHaveLength(2);
    expect(screen.getByTestId("financials-skeleton-table")).toBeInTheDocument();
  });

  it("renders the drill-down layout: 3 tiles, 3 chart cards and no table block", () => {
    render(<FinancialsSkeleton variant="project" />);

    expect(screen.getByTestId("financials-skeleton")).toBeInTheDocument();
    expect(screen.getAllByTestId("financials-skeleton-tile")).toHaveLength(3);
    expect(screen.getAllByTestId("financials-skeleton-chart-card")).toHaveLength(3);
    expect(screen.queryByTestId("financials-skeleton-table")).not.toBeInTheDocument();
  });
});
