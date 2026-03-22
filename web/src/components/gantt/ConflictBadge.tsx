"use client";

import { Badge } from "@/components/ui/badge";
import { AlertTriangle } from "lucide-react";
import { format } from "date-fns";

interface ConflictBadgeProps {
  trade1: string;
  trade2: string;
  zone: string;
  date: string;
}

export function ConflictBadge({ trade1, trade2, zone, date }: ConflictBadgeProps) {
  const formattedDate = (() => {
    try {
      return format(new Date(date), "MMM d, yyyy");
    } catch {
      return date;
    }
  })();

  return (
    <Badge
      variant="outline"
      className="bg-yellow-100 text-yellow-800 border-yellow-400 flex items-center gap-1.5 px-2.5 py-1 h-auto text-xs font-medium"
      role="alert"
      aria-live="polite"
    >
      <AlertTriangle className="h-3.5 w-3.5 flex-shrink-0" aria-hidden="true" />
      <span>
        Conflict: {trade1} and {trade2} overlap in {zone} on {formattedDate}
      </span>
    </Badge>
  );
}
