import type { DateOverride } from "@/types/api";
import { Button } from "@/components/ui/button";
import {
  dedupeOverridesByDate,
  formatOverrideDate,
  parseOverrideDate,
} from "../_lib/schedule-overrides";

function overrideSummary(override: DateOverride): string {
  if (override.is_unavailable) return "Unavailable";
  if (override.start_time && override.end_time) {
    return `${override.start_time.slice(0, 5)} – ${override.end_time.slice(0, 5)}`;
  }
  return "Custom hours";
}

interface OverrideListProps {
  overrides: DateOverride[] | undefined;
  onRemove: (date: Date) => void;
}

export function OverrideList({ overrides, onRemove }: OverrideListProps) {
  return (
    <div className="space-y-2">
      <p className="text-sm font-semibold text-gray-700">Current Overrides</p>
      {!overrides || overrides.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No date overrides set. Select a date above to add one.
        </p>
      ) : (
        <div className="space-y-2">
          {dedupeOverridesByDate(overrides).map((override) => (
            <div
              key={override.override_date}
              className="flex items-center justify-between rounded-md border px-4 py-2 text-sm"
            >
              <span className="text-gray-900">
                {formatOverrideDate(parseOverrideDate(override.override_date))}
              </span>
              <span className="text-muted-foreground">
                {overrideSummary(override)}
              </span>
              <Button
                variant="ghost"
                size="sm"
                className="text-destructive hover:text-destructive"
                onClick={() => onRemove(parseOverrideDate(override.override_date))}
              >
                Remove
              </Button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
