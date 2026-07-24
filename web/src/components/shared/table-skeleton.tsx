import { Skeleton } from "@/components/ui/skeleton";

const DEFAULT_ROW_COUNT = 5;

interface TableSkeletonProps {
  columnWidths: string[];
  rowCount?: number;
}

export function TableSkeleton({
  columnWidths,
  rowCount = DEFAULT_ROW_COUNT,
}: TableSkeletonProps) {
  return (
    <div className="divide-y">
      {Array.from({ length: rowCount }).map((_, rowIndex) => (
        <div key={rowIndex} className="flex items-center gap-4 px-4 h-12">
          {columnWidths.map((width, columnIndex) => (
            <Skeleton key={columnIndex} className={`h-4 ${width}`} />
          ))}
        </div>
      ))}
    </div>
  );
}
