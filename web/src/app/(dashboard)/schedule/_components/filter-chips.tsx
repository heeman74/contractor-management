"use client";

import { X } from "lucide-react";

interface FilterChipsProps {
  filterTrades: string[];
  filterStatuses: string[];
  filterContractors: string[];
  contractorNames: Map<string, string>;
  onRemoveTrade: (trade: string) => void;
  onRemoveStatus: (status: string) => void;
  onRemoveContractor: (id: string) => void;
  onClearAll: () => void;
}

export function FilterChips({
  filterTrades,
  filterStatuses,
  filterContractors,
  contractorNames,
  onRemoveTrade,
  onRemoveStatus,
  onRemoveContractor,
  onClearAll,
}: FilterChipsProps) {
  const hasFilters =
    filterTrades.length > 0 ||
    filterStatuses.length > 0 ||
    filterContractors.length > 0;

  if (!hasFilters) return null;

  return (
    <div className="flex flex-wrap items-center gap-2 py-2">
      {filterTrades.map((trade) => (
        <span
          key={`trade-${trade}`}
          className="inline-flex items-center gap-1 rounded-full bg-gray-100 text-gray-700 text-xs font-medium px-3 py-1"
        >
          Trade: {trade}
          <button
            type="button"
            onClick={() => onRemoveTrade(trade)}
            aria-label={`Remove Trade: ${trade} filter`}
            className="text-gray-400 hover:text-gray-700 cursor-pointer"
          >
            <X className="h-3 w-3" />
          </button>
        </span>
      ))}

      {filterStatuses.map((status) => (
        <span
          key={`status-${status}`}
          className="inline-flex items-center gap-1 rounded-full bg-gray-100 text-gray-700 text-xs font-medium px-3 py-1"
        >
          Status: {status}
          <button
            type="button"
            onClick={() => onRemoveStatus(status)}
            aria-label={`Remove Status: ${status} filter`}
            className="text-gray-400 hover:text-gray-700 cursor-pointer"
          >
            <X className="h-3 w-3" />
          </button>
        </span>
      ))}

      {filterContractors.map((id) => (
        <span
          key={`contractor-${id}`}
          className="inline-flex items-center gap-1 rounded-full bg-gray-100 text-gray-700 text-xs font-medium px-3 py-1"
        >
          Contractor: {contractorNames.get(id) ?? id}
          <button
            type="button"
            onClick={() => onRemoveContractor(id)}
            aria-label={`Remove Contractor: ${contractorNames.get(id) ?? id} filter`}
            className="text-gray-400 hover:text-gray-700 cursor-pointer"
          >
            <X className="h-3 w-3" />
          </button>
        </span>
      ))}

      <button
        type="button"
        onClick={onClearAll}
        className="text-sm text-blue-600 hover:underline cursor-pointer ml-2"
      >
        Clear all
      </button>
    </div>
  );
}
