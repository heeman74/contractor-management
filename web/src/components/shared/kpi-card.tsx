import Link from "next/link";
import { type LucideIcon } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

interface KpiCardProps {
  title: string;
  value: number | string;
  icon: LucideIcon;
  href: string;
  loading?: boolean;
}

export function KpiCard({ title, value, icon: Icon, href, loading = false }: KpiCardProps) {
  if (loading) {
    return (
      <Card className="hover:shadow-md transition-shadow">
        <CardContent className="pt-4">
          <div className="flex items-center justify-between">
            <Skeleton className="h-4 w-24" />
            <Skeleton className="h-8 w-8 rounded-md" />
          </div>
          <Skeleton className="mt-3 h-8 w-16" />
        </CardContent>
      </Card>
    );
  }

  return (
    <Link href={href} className="block">
      <Card className="hover:shadow-md transition-shadow hover:ring-indigo-200 cursor-pointer">
        <CardContent className="pt-4">
          <div className="flex items-center justify-between">
            <p className="text-sm font-medium text-gray-500">{title}</p>
            <div className="rounded-md bg-indigo-50 p-2">
              <Icon className="h-4 w-4 text-indigo-600" />
            </div>
          </div>
          <p className="mt-2 text-3xl font-bold text-gray-900">{value}</p>
        </CardContent>
      </Card>
    </Link>
  );
}
