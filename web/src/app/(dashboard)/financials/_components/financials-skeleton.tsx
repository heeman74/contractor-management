"use client";

import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

const SUMMARY_TILE_COUNT = 3;
const HALF_WIDTH_CHART_COUNT = 2;

/** The loading shape of both financial routes. The Reports page's own skeleton is
 *  deliberately not reused: the layouts differ, and importing it would couple the
 *  two pages. */
export function FinancialsSkeleton({ variant }: { variant: "company" | "project" }) {
  return (
    <div className="space-y-6" data-testid="financials-skeleton">
      <SkeletonTiles />
      {variant === "project" && <SkeletonChartCard />}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        {Array.from({ length: HALF_WIDTH_CHART_COUNT }).map((_, index) => (
          <SkeletonChartCard key={index} />
        ))}
      </div>
      {variant === "company" && <SkeletonTableBlock />}
    </div>
  );
}

function SkeletonTiles() {
  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
      {Array.from({ length: SUMMARY_TILE_COUNT }).map((_, index) => (
        <Card key={index} data-testid="financials-skeleton-tile">
          <CardContent className="pt-4">
            <Skeleton className="h-4 w-24" />
            <Skeleton className="mt-1 h-8 w-32" />
            <Skeleton className="mt-1 h-4 w-20" />
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

function SkeletonChartCard() {
  return (
    <Card data-testid="financials-skeleton-chart-card">
      <CardContent className="pt-4">
        <div className="flex items-center justify-between">
          <Skeleton className="h-4 w-24" />
          <Skeleton className="h-8 w-8 rounded-md" />
        </div>
        <Skeleton className="mt-2 h-8 w-20" />
        <Skeleton className="mt-4 h-[280px] w-full rounded-md" />
      </CardContent>
    </Card>
  );
}

function SkeletonTableBlock() {
  return (
    <Card data-testid="financials-skeleton-table">
      <CardContent className="pt-4">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="mt-4 h-[240px] w-full rounded-md" />
      </CardContent>
    </Card>
  );
}
