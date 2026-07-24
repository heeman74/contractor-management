"use client";

import { Plus, Check, ChevronsUpDown } from "lucide-react";
import { Label } from "@/components/ui/label";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import type { TradeCatalogResponse } from "@/types/projects";

const DEFAULT_TRADE_COLOR = "#6b7280";

interface TradeNameComboboxProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  tradeName: string;
  tradeSearch: string;
  onTradeSearchChange: (value: string) => void;
  filteredCatalog: TradeCatalogResponse[];
  selectedCatalogId: string | null;
  showNewTradeOption: boolean;
  onSelectEntry: (entry: TradeCatalogResponse) => void;
  onSelectNewTrade: () => void;
}

export function TradeNameCombobox({
  open,
  onOpenChange,
  tradeName,
  tradeSearch,
  onTradeSearchChange,
  filteredCatalog,
  selectedCatalogId,
  showNewTradeOption,
  onSelectEntry,
  onSelectNewTrade,
}: TradeNameComboboxProps) {
  return (
    <div className="flex flex-col gap-1.5">
      <Label>Trade Name *</Label>
      <Popover open={open} onOpenChange={onOpenChange}>
        <PopoverTrigger
          className="flex h-9 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
          aria-label="Select trade name"
          data-testid="trade-name-combobox"
        >
          <span className={cn(!tradeName && "text-muted-foreground")}>
            {tradeName || "Search or create trade..."}
          </span>
          <ChevronsUpDown className="ml-2 h-4 w-4 flex-shrink-0 text-gray-400" />
        </PopoverTrigger>
        <PopoverContent className="w-full min-w-[280px] p-0" align="start">
          <div className="flex flex-col">
            <input
              className="w-full border-b border-input bg-transparent px-3 py-2 text-sm outline-none placeholder:text-muted-foreground"
              placeholder="Search trades..."
              value={tradeSearch}
              onChange={(e) => onTradeSearchChange(e.target.value)}
              autoFocus
              data-testid="trade-search-input"
            />
            <div className="max-h-60 overflow-y-auto py-1">
              {filteredCatalog.map((entry) => (
                <button
                  key={entry.id}
                  type="button"
                  className="flex w-full cursor-pointer items-center gap-2 px-3 py-2 text-sm hover:bg-accent hover:text-accent-foreground"
                  onClick={() => onSelectEntry(entry)}
                >
                  <span
                    className="inline-block h-3 w-3 flex-shrink-0 rounded-full"
                    style={{ backgroundColor: entry.color || DEFAULT_TRADE_COLOR }}
                  />
                  <span className="flex-1 text-left">{entry.name}</span>
                  {selectedCatalogId === entry.id && (
                    <Check className="h-3.5 w-3.5 text-foreground" />
                  )}
                </button>
              ))}
              {showNewTradeOption && (
                <button
                  type="button"
                  className="flex w-full cursor-pointer items-center gap-2 px-3 py-2 text-sm text-foreground hover:bg-secondary"
                  onClick={onSelectNewTrade}
                  data-testid="create-new-trade-option"
                >
                  <Plus className="h-3.5 w-3.5" />
                  <span>Create new trade: &quot;{tradeSearch}&quot;</span>
                </button>
              )}
              {filteredCatalog.length === 0 && !showNewTradeOption && (
                <p className="px-3 py-2 text-sm text-gray-500">
                  No trades found. Type to create a new one.
                </p>
              )}
            </div>
          </div>
        </PopoverContent>
      </Popover>
    </div>
  );
}
