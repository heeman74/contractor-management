"use client";

import { ChevronDown, ChevronUp } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuCheckboxItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useAppSelector, useAppDispatch } from "@/store/hooks";
import { toggleFilterToolbar } from "@/store/slices/schedule-slice";
import type { ContractorResource } from "@/types/schedule";

interface FilterToolbarProps {
  contractors: ContractorResource[];
  filterTrades: string[];
  filterStatuses: string[];
  filterContractors: string[];
  onFiltersChange: (
    trades: string[],
    statuses: string[],
    contractors: string[]
  ) => void;
}

const STATUS_OPTIONS = [
  "quote",
  "scheduled",
  "in_progress",
  "complete",
  "invoiced",
];

/** Format snake_case status values for display (e.g. "in_progress" -> "In Progress") */
function formatStatusLabel(status: string): string {
  return status
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

export function FilterToolbar({
  contractors,
  filterTrades,
  filterStatuses,
  filterContractors,
  onFiltersChange,
}: FilterToolbarProps) {
  const dispatch = useAppDispatch();
  const filterToolbarCollapsed = useAppSelector(
    (state) => state.schedule.filterToolbarCollapsed
  );

  // Derive unique trade types from the contractor list
  const tradeTypes = [
    ...new Set(
      contractors.map((c) => c.tradeType).filter((t): t is string => Boolean(t))
    ),
  ];

  const triggerClass =
    "inline-flex items-center gap-1.5 rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-900";

  return (
    <div>
      {/* Toggle button row — shown inline with main toolbar in page layout */}
      <div className="flex items-center justify-end py-1">
        <button
          type="button"
          onClick={() => dispatch(toggleFilterToolbar())}
          className="inline-flex items-center gap-1 text-sm font-medium text-gray-600 hover:text-gray-900"
          aria-expanded={!filterToolbarCollapsed}
          aria-label={filterToolbarCollapsed ? "Show filters" : "Hide filters"}
        >
          {filterToolbarCollapsed ? (
            <>
              Filters
              <ChevronDown className="h-4 w-4" />
            </>
          ) : (
            <>
              Hide Filters
              <ChevronUp className="h-4 w-4" />
            </>
          )}
        </button>
      </div>

      {/* Filter dropdowns — shown only when expanded */}
      {!filterToolbarCollapsed && (
        <div className="flex items-center gap-3 py-2 border-b border-gray-100">
          {/* Trade filter */}
          <DropdownMenu>
            <DropdownMenuTrigger
              className={triggerClass}
              aria-label="Filter by Trade"
            >
              Trade:{" "}
              {filterTrades.length > 0
                ? `${filterTrades.length} selected`
                : "All"}
              <ChevronDown className="h-3.5 w-3.5" />
            </DropdownMenuTrigger>
            <DropdownMenuContent>
              {tradeTypes.length === 0 ? (
                <p className="px-2 py-1.5 text-sm text-gray-400">
                  No trade types
                </p>
              ) : (
                tradeTypes.map((trade) => (
                  <DropdownMenuCheckboxItem
                    key={trade}
                    checked={filterTrades.includes(trade)}
                    onCheckedChange={(checked) => {
                      const newTrades = checked
                        ? [...filterTrades, trade]
                        : filterTrades.filter((t) => t !== trade);
                      onFiltersChange(newTrades, filterStatuses, filterContractors);
                    }}
                  >
                    {trade}
                  </DropdownMenuCheckboxItem>
                ))
              )}
            </DropdownMenuContent>
          </DropdownMenu>

          {/* Status filter */}
          <DropdownMenu>
            <DropdownMenuTrigger
              className={triggerClass}
              aria-label="Filter by Status"
            >
              Status:{" "}
              {filterStatuses.length > 0
                ? `${filterStatuses.length} selected`
                : "All"}
              <ChevronDown className="h-3.5 w-3.5" />
            </DropdownMenuTrigger>
            <DropdownMenuContent>
              {STATUS_OPTIONS.map((status) => (
                <DropdownMenuCheckboxItem
                  key={status}
                  checked={filterStatuses.includes(status)}
                  onCheckedChange={(checked) => {
                    const newStatuses = checked
                      ? [...filterStatuses, status]
                      : filterStatuses.filter((s) => s !== status);
                    onFiltersChange(filterTrades, newStatuses, filterContractors);
                  }}
                >
                  {formatStatusLabel(status)}
                </DropdownMenuCheckboxItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>

          {/* Contractor filter */}
          <DropdownMenu>
            <DropdownMenuTrigger
              className={triggerClass}
              aria-label="Filter by Contractor"
            >
              Contractors:{" "}
              {filterContractors.length > 0
                ? `${filterContractors.length} selected`
                : "All"}
              <ChevronDown className="h-3.5 w-3.5" />
            </DropdownMenuTrigger>
            <DropdownMenuContent>
              {contractors.length === 0 ? (
                <p className="px-2 py-1.5 text-sm text-gray-400">
                  No contractors
                </p>
              ) : (
                contractors.map((c) => (
                  <DropdownMenuCheckboxItem
                    key={c.id}
                    checked={filterContractors.includes(c.id)}
                    onCheckedChange={(checked) => {
                      const newContractors = checked
                        ? [...filterContractors, c.id]
                        : filterContractors.filter((id) => id !== c.id);
                      onFiltersChange(filterTrades, filterStatuses, newContractors);
                    }}
                  >
                    {c.name}
                  </DropdownMenuCheckboxItem>
                ))
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      )}
    </div>
  );
}
