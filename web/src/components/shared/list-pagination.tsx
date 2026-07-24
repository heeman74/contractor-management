import { Button } from "@/components/ui/button";

interface ListPaginationProps {
  page: number;
  hasNextPage: boolean;
  totalPages?: number;
  onPageChange: (page: number) => void;
}

export function ListPagination({
  page,
  hasNextPage,
  totalPages,
  onPageChange,
}: ListPaginationProps) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-sm text-gray-500">
        {totalPages !== undefined
          ? `Showing page ${page} of ${totalPages}`
          : `Showing page ${page}`}
      </span>
      <div className="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() => onPageChange(page - 1)}
          disabled={page === 1}
        >
          Previous
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => onPageChange(page + 1)}
          disabled={!hasNextPage}
        >
          Next
        </Button>
      </div>
    </div>
  );
}
