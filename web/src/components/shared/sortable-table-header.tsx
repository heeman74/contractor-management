import { ArrowDown, ArrowUp, ArrowUpDown } from "lucide-react";
import { cn } from "@/lib/utils";
import { TableHead } from "@/components/ui/table";
import type { SortDirection } from "@/hooks/use-list-table-filters";

const BASE_HEADER_CLASSES =
  "text-xs font-semibold text-gray-500 uppercase tracking-wide";
const SORTABLE_CLASSES = "cursor-pointer select-none";

function SortIcon({ isActive, direction }: { isActive: boolean; direction: SortDirection }) {
  if (!isActive) {
    return <ArrowUpDown className="ml-1 inline h-3 w-3 text-gray-400" />;
  }
  return direction === "asc" ? (
    <ArrowUp className="ml-1 inline h-3 w-3 text-gray-700" />
  ) : (
    <ArrowDown className="ml-1 inline h-3 w-3 text-gray-700" />
  );
}

interface SortableTableHeaderProps<TColumn extends string> {
  column: TColumn;
  label: string;
  activeColumn: TColumn;
  direction: SortDirection;
  onSort: (column: TColumn) => void;
  className?: string;
}

export function SortableTableHeader<TColumn extends string>({
  column,
  label,
  activeColumn,
  direction,
  onSort,
  className,
}: SortableTableHeaderProps<TColumn>) {
  return (
    <TableHead
      className={cn(BASE_HEADER_CLASSES, SORTABLE_CLASSES, className)}
      onClick={() => onSort(column)}
    >
      {label}
      <SortIcon isActive={activeColumn === column} direction={direction} />
    </TableHead>
  );
}

export function PlainTableHeader({
  label,
  className,
}: {
  label: string;
  className?: string;
}) {
  return (
    <TableHead className={cn(BASE_HEADER_CLASSES, className)}>{label}</TableHead>
  );
}
