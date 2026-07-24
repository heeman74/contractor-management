"use client";

import { use } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { Briefcase, Clock } from "lucide-react";
import { toast } from "sonner";
import { apiGet } from "@/lib/api-client";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Separator } from "@/components/ui/separator";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { ContractorListItem, Job, WeeklyBlock } from "@/types/api";

const DAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
// day_of_week: 0 = Monday ... 6 = Sunday (backend convention)

function formatTimeRange(blocks: WeeklyBlock[]): string {
  if (blocks.length === 0) return "";
  const sorted = [...blocks].sort((a, b) => a.block_index - b.block_index);
  // Format as HH:MM - HH:MM for each block
  return sorted
    .map((b) => {
      const start = b.start_time.slice(0, 5);
      const end = b.end_time.slice(0, 5);
      return `${start}–${end}`;
    })
    .join(", ");
}

function getMostCommonTradeType(jobs: Job[]): string | null {
  if (!jobs || jobs.length === 0) return null;
  const counts: Record<string, number> = {};
  for (const job of jobs) {
    if (job.trade_type) {
      counts[job.trade_type] = (counts[job.trade_type] ?? 0) + 1;
    }
  }
  if (Object.keys(counts).length === 0) return null;
  return Object.entries(counts).sort((a, b) => b[1] - a[1])[0][0];
}

function calcHoursThisWeek(weeklySchedule: Record<string, WeeklyBlock[]> | undefined): number {
  if (!weeklySchedule) return 0;
  let totalMinutes = 0;
  for (const dayBlocks of Object.values(weeklySchedule)) {
    for (const block of dayBlocks) {
      // Parse HH:MM:SS or HH:MM
      const [sh, sm] = block.start_time.split(":").map(Number);
      const [eh, em] = block.end_time.split(":").map(Number);
      const startMin = sh * 60 + sm;
      const endMin = eh * 60 + em;
      totalMinutes += Math.max(0, endMin - startMin);
    }
  }
  return Math.round((totalMinutes / 60) * 10) / 10; // one decimal
}

export default function ContractorProfilePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id: contractorId } = use(params);
  const router = useRouter();

  // Query 1: All users (to find contractor info)
  const { data: allUsers, isLoading: usersLoading, isError: usersError } = useQuery({
    queryKey: ["users"],
    queryFn: () => apiGet<ContractorListItem[]>("/api/v1/users/"),
  });
  const contractor = allUsers?.find((u) => u.id === contractorId);

  // Query 2: Assigned jobs
  const { data: jobs, isLoading: jobsLoading } = useQuery({
    queryKey: ["contractor-jobs", contractorId],
    queryFn: () => apiGet<Job[]>(`/api/v1/jobs/?contractor_id=${contractorId}`),
    enabled: !!contractorId,
  });

  // Query 3: Weekly schedule
  const { data: weeklySchedule, isLoading: scheduleLoading } = useQuery({
    queryKey: ["weekly-schedule", contractorId],
    queryFn: () =>
      apiGet<Record<string, WeeklyBlock[]>>(
        `/api/v1/scheduling/schedules/${contractorId}/weekly`
      ),
    enabled: !!contractorId,
  });

  const isLoading = usersLoading || jobsLoading || scheduleLoading;

  if (usersError) {
    toast.error("Failed to load contractor profile. Please refresh the page.", {
      duration: Infinity,
    });
  }

  // Derived stats
  const activeJobsCount = jobs?.filter(
    (j) => j.status === "scheduled" || j.status === "in_progress"
  ).length ?? 0;

  const hoursThisWeek = calcHoursThisWeek(weeklySchedule);

  const mostCommonTrade = getMostCommonTradeType(jobs ?? []);

  const initials =
    `${(contractor?.first_name?.[0] ?? "").toUpperCase()}${(contractor?.last_name?.[0] ?? "").toUpperCase()}` || "?";

  const hasSchedule =
    weeklySchedule && Object.values(weeklySchedule).some((blocks) => blocks.length > 0);

  if (isLoading) {
    return (
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <SkeletonProfile />
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* Back link + Page header */}
      <div className="space-y-1">
        <Link
          href="/contractors"
          className="text-sm text-gray-500 hover:text-gray-700 inline-flex items-center gap-1"
        >
          ← Back to Contractors
        </Link>
        <h1 className="text-xl font-semibold text-gray-900">
          {contractor
            ? `${contractor.first_name ?? ""} ${contractor.last_name ?? ""}`.trim() ||
              contractor.email
            : "Contractor Profile"}
        </h1>
      </div>

      {/* Two-column layout */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        {/* Main column */}
        <div className="space-y-6">
          {/* Weekly Schedule card */}
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-4">
              <CardTitle className="text-base font-semibold text-gray-900">
                Weekly Schedule
              </CardTitle>
              <Button
                size="sm"
                onClick={() => router.push(`/contractors/${contractorId}/schedule`)}
              >
                Edit Schedule
              </Button>
            </CardHeader>
            <CardContent>
              {!hasSchedule ? (
                <p className="text-sm text-gray-500">
                  No working hours configured. Click Edit Schedule to set availability.
                </p>
              ) : (
                <div className="grid grid-cols-7 gap-1">
                  {DAY_LABELS.map((label, dayIndex) => {
                    const dayBlocks = weeklySchedule?.[String(dayIndex)] ?? [];
                    const hasBlocks = dayBlocks.length > 0;
                    return (
                      <div key={dayIndex} className="flex flex-col items-center gap-1">
                        <span className="text-xs font-medium text-gray-500">{label}</span>
                        <div
                          className={`w-full rounded px-1 py-2 text-center ${
                            hasBlocks
                              ? "bg-secondary text-foreground"
                              : "bg-gray-100 text-gray-400"
                          }`}
                        >
                          {hasBlocks ? (
                            <span className="text-xs">{formatTimeRange(dayBlocks)}</span>
                          ) : (
                            <span className="text-xs">Off</span>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Assigned Jobs card */}
          <Card>
            <CardHeader className="pb-4">
              <CardTitle className="text-base font-semibold text-gray-900">
                Assigned Jobs
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {!jobs || jobs.length === 0 ? (
                <div className="px-6 py-8 text-center">
                  <p className="text-sm text-gray-500">
                    No jobs currently assigned to this contractor.
                  </p>
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Job #
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Title
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Status
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Client
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Date
                      </TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {jobs.map((job) => (
                      <TableRow
                        key={job.id}
                        className="cursor-pointer hover:bg-gray-50"
                        onClick={() => router.push(`/jobs/${job.id}`)}
                      >
                        <TableCell className="py-3 px-4 font-mono text-sm text-gray-900">
                          {job.id.slice(0, 8).toUpperCase()}
                        </TableCell>
                        <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-xs">
                          {job.description}
                        </TableCell>
                        <TableCell className="py-3 px-4">
                          <StatusBadge status={job.status} size="sm" />
                        </TableCell>
                        <TableCell className="py-3 px-4 text-sm text-gray-500">
                          {job.client_name ?? "—"}
                        </TableCell>
                        <TableCell className="py-3 px-4 text-sm text-gray-500">
                          {new Date(job.created_at).toLocaleDateString()}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Sidebar */}
        <div className="space-y-4">
          {/* Contact card */}
          <Card>
            <CardContent className="pt-6 space-y-4">
              {/* Avatar + Name */}
              <div className="flex items-center gap-3">
                <Avatar size="lg">
                  <AvatarFallback>{initials}</AvatarFallback>
                </Avatar>
                <div>
                  <p className="text-sm font-semibold text-gray-900">
                    {contractor
                      ? `${contractor.first_name ?? ""} ${contractor.last_name ?? ""}`.trim() ||
                        contractor.email
                      : "—"}
                  </p>
                  <p className="text-xs text-gray-500">{contractor?.email ?? "—"}</p>
                </div>
              </div>
              <Separator />
              <div className="space-y-2">
                <div>
                  <p className="text-xs text-gray-500">Phone</p>
                  <p className="text-sm text-gray-900">{contractor?.phone ?? "—"}</p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Trade badge */}
          <Card>
            <CardContent className="pt-6 space-y-2">
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                Trade
              </p>
              {mostCommonTrade ? (
                <Badge className="bg-gray-100 text-gray-700 border-0">
                  {mostCommonTrade}
                </Badge>
              ) : (
                <Badge className="bg-gray-100 text-gray-700 border-0">
                  Contractor
                </Badge>
              )}
            </CardContent>
          </Card>

          {/* Quick Stats */}
          <Card>
            <CardContent className="pt-6 space-y-4">
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                Quick Stats
              </p>
              <div className="grid grid-cols-2 gap-4">
                <div className="flex flex-col gap-1">
                  <div className="rounded-md bg-secondary p-2 w-fit">
                    <Briefcase className="h-4 w-4 text-foreground" />
                  </div>
                  <p className="text-2xl font-bold text-gray-900">{activeJobsCount}</p>
                  <p className="text-xs text-gray-500">Active Jobs</p>
                </div>
                <div className="flex flex-col gap-1">
                  <div className="rounded-md bg-secondary p-2 w-fit">
                    <Clock className="h-4 w-4 text-foreground" />
                  </div>
                  <p className="text-2xl font-bold text-gray-900">{hoursThisWeek}h</p>
                  <p className="text-xs text-gray-500">Hours This Week</p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Average Rating */}
          <Card>
            <CardContent className="pt-6 space-y-2">
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                Average Rating
              </p>
              <p className="text-sm text-gray-500">No ratings yet</p>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}

function SkeletonProfile() {
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <Skeleton className="h-4 w-32" />
        <Skeleton className="h-6 w-48" />
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        <div className="space-y-6">
          <Card>
            <CardHeader>
              <Skeleton className="h-5 w-36" />
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-7 gap-1">
                {[...Array(7)].map((_, i) => (
                  <Skeleton key={i} className="h-16 w-full" />
                ))}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <Skeleton className="h-5 w-32" />
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {[...Array(3)].map((_, i) => (
                  <Skeleton key={i} className="h-10 w-full" />
                ))}
              </div>
            </CardContent>
          </Card>
        </div>
        <div className="space-y-4">
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <Skeleton className="h-10 w-10 rounded-full" />
                <div className="space-y-1">
                  <Skeleton className="h-4 w-32" />
                  <Skeleton className="h-3 w-40" />
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <Skeleton className="h-6 w-24" />
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-6">
              <div className="grid grid-cols-2 gap-4">
                <Skeleton className="h-20 w-full" />
                <Skeleton className="h-20 w-full" />
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
