"use client";

import { Plus, Check, ChevronsUpDown, Trash2 } from "lucide-react";
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
  catalogIsEmpty: boolean;
  isSeedingDefaults: boolean;
  onSelectEntry: (entry: TradeCatalogResponse) => void;
  onSelectNewTrade: () => void;
  onRemoveEntry: (id: string) => void;
  onSeedDefaults: () => void;
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
  catalogIsEmpty,
  isSeedingDefaults,
  onSelectEntry,
  onSelectNewTrade,
  onRemoveEntry,
  onSeedDefaults,
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
                <div
                  key={entry.id}
                  className="group flex w-full items-center gap-2 px-3 py-2 text-sm hover:bg-accent hover:text-accent-foreground"
                >
                  <button
                    type="button"
                    className="flex flex-1 cursor-pointer items-center gap-2 text-left"
                    onClick={() => onSelectEntry(entry)}
                  >
                    <span
                      className="inline-block h-3 w-3 flex-shrink-0 rounded-full"
                      style={{ backgroundColor: entry.color || DEFAULT_TRADE_COLOR }}
                    />
                    <span className="flex-1">{entry.name}</span>
                    {selectedCatalogId === entry.id && (
                      <Check className="h-3.5 w-3.5 text-foreground" />
                    )}
                  </button>
                  <button
                    type="button"
                    onClick={() => onRemoveEntry(entry.id)}
                    aria-label={`Remove ${entry.name}`}
                    className="flex-shrink-0 rounded p-1 text-gray-400 opacity-0 hover:bg-gray-100 hover:text-destructive focus:opacity-100 group-hover:opacity-100"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                </div>
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
                <div className="px-3 py-2">
                  {catalogIsEmpty ? (
                    <button
                      type="button"
                      onClick={onSeedDefaults}
                      disabled={isSeedingDefaults}
                      className="flex w-full items-center gap-2 rounded text-sm text-foreground hover:underline disabled:opacity-50"
                      data-testid="seed-default-trades"
                    >
                      <Plus className="h-3.5 w-3.5" />
                      {isSeedingDefaults ? "Adding defaults…" : "Add default trades"}
                    </button>
                  ) : (
                    <p className="text-sm text-gray-500">
                      No trades found. Type to create a new one.
                    </p>
                  )}
                </div>
              )}
            </div>
          </div>
        </PopoverContent>
      </Popover>
    </div>
  );
}
