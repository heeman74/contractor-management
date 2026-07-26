"use client";

import { Trash2 } from "lucide-react";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { formatCurrency, formatDate } from "@/lib/format";
import { useDeleteCostEntry } from "../hooks";
import type { CostEntry } from "../types";

interface CostEntryListProps {
  entries: CostEntry[] | undefined;
  emptyLabel?: string;
}

export function CostEntryList({
  entries,
  emptyLabel = "No cost entries yet.",
}: CostEntryListProps) {
  const { can } = usePermissions();
  const deleteCostEntry = useDeleteCostEntry();

  if (!entries || entries.length === 0) {
    return <p className="text-sm text-gray-500">{emptyLabel}</p>;
  }

  return (
    <div className="space-y-2">
      {entries.map((entry) => (
        <div
          key={entry.id}
          className="flex items-center justify-between gap-3 rounded-lg border border-gray-200 bg-white p-3"
        >
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-gray-800">
              {entry.categoryName ?? "Uncategorized"}
              {entry.vendor ? ` · ${entry.vendor}` : ""}
            </p>
            <p className="truncate text-xs text-gray-500">
              {formatDate(entry.incurredDate)}
              {entry.note ? ` · ${entry.note}` : ""}
            </p>
          </div>
          <div className="flex flex-shrink-0 items-center gap-3">
            <span className="text-sm font-semibold text-gray-900">
              {formatCurrency(entry.amount)}
            </span>
            {can("finance.manage") && (
              <button
                onClick={() => deleteCostEntry.mutate(entry.id)}
                disabled={deleteCostEntry.isPending}
                aria-label={`Delete cost entry ${entry.categoryName ?? entry.id}`}
                className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-destructive"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
