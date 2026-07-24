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
      <Card>
        <CardContent className="pt-4">
          <div className="flex items-center justify-between">
            <Skeleton className="h-3 w-24" />
            <Skeleton className="h-8 w-8 rounded-md" />
          </div>
          <Skeleton className="mt-3 h-8 w-16" />
        </CardContent>
      </Card>
    );
  }

  return (
    <Link href={href} className="group block">
      <Card className="relative cursor-pointer overflow-hidden transition-all hover:ring-1 hover:ring-brand/50 hover:shadow-sm">
        {/* hi-vis rule wipes in on hover — the one accent */}
        <span className="absolute inset-x-0 top-0 h-0.5 origin-left scale-x-0 bg-brand transition-transform duration-300 group-hover:scale-x-100" />
        <CardContent className="pt-4">
          <div className="flex items-center justify-between">
            <p className="eyebrow text-muted-foreground">{title}</p>
            <div className="rounded-md bg-secondary p-2 text-foreground/70 transition-colors group-hover:text-foreground">
              <Icon className="h-4 w-4" />
            </div>
          </div>
          <p className="num mt-2 text-3xl font-bold text-foreground">{value}</p>
        </CardContent>
      </Card>
    </Link>
  );
}
