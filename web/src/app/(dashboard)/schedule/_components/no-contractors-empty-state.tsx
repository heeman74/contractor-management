import Link from "next/link";
import { CalendarOff } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export function NoContractorsEmptyState() {
  return (
    <div className="flex flex-col items-center justify-center py-24 text-center">
      <CalendarOff className="h-12 w-12 text-gray-300 mb-4" />
      <h3 className="text-base font-semibold text-gray-900 mb-1">
        No contractors yet
      </h3>
      <p className="text-sm text-gray-500 mb-6">
        Add your team to start scheduling jobs.
      </p>
      <Link
        href="/contractors"
        className={cn(buttonVariants({ variant: "outline", size: "sm" }))}
      >
        Add Contractors
      </Link>
    </div>
  );
}
