import React from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import type { TradeCatalogResponse } from "@/types/projects";

// The popover is built on @base-ui/react, which doesn't render under jsdom.
// Replace it with pass-through wrappers so the list/remove/seed logic — the
// part this test cares about — renders synchronously.
jest.mock("@/components/ui/popover", () => ({
  Popover: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  PopoverTrigger: ({ children, ...props }: React.ComponentProps<"button">) => (
    <button {...props}>{children}</button>
  ),
  PopoverContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

import { TradeNameCombobox } from "../TradeNameCombobox";

function entry(id: string, name: string): TradeCatalogResponse {
  return { id, name, color: "#F59E0B" } as TradeCatalogResponse;
}

const baseProps = {
  open: true,
  onOpenChange: jest.fn(),
  tradeName: "",
  tradeSearch: "",
  onTradeSearchChange: jest.fn(),
  filteredCatalog: [] as TradeCatalogResponse[],
  selectedCatalogId: null,
  showNewTradeOption: false,
  catalogIsEmpty: false,
  isSeedingDefaults: false,
  onSelectEntry: jest.fn(),
  onSelectNewTrade: jest.fn(),
  onRemoveEntry: jest.fn(),
  onSeedDefaults: jest.fn(),
};

describe("TradeNameCombobox", () => {
  test("renders catalog entries with a remove button that reports the id", () => {
    const onRemoveEntry = jest.fn();
    render(
      <TradeNameCombobox
        {...baseProps}
        filteredCatalog={[entry("t1", "Electrical")]}
        onRemoveEntry={onRemoveEntry}
      />
    );

    expect(screen.getByText("Electrical")).toBeInTheDocument();
    fireEvent.click(screen.getByLabelText("Remove Electrical"));
    expect(onRemoveEntry).toHaveBeenCalledWith("t1");
  });

  test("offers to seed defaults when the catalog is entirely empty", () => {
    const onSeedDefaults = jest.fn();
    render(
      <TradeNameCombobox
        {...baseProps}
        filteredCatalog={[]}
        catalogIsEmpty
        onSeedDefaults={onSeedDefaults}
      />
    );

    fireEvent.click(screen.getByTestId("seed-default-trades"));
    expect(onSeedDefaults).toHaveBeenCalled();
  });

  test("shows the create hint (not the seed button) when a search simply misses", () => {
    render(
      <TradeNameCombobox
        {...baseProps}
        filteredCatalog={[]}
        tradeSearch="xyz"
        catalogIsEmpty={false}
      />
    );

    expect(
      screen.getByText(/No trades found. Type to create a new one./i)
    ).toBeInTheDocument();
    expect(screen.queryByTestId("seed-default-trades")).not.toBeInTheDocument();
  });
});
