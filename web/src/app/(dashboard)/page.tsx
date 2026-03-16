"use client";

import { useQuery } from "@tanstack/react-query";
import { Briefcase, FileText, Receipt, Calendar } from "lucide-react";
import { toast } from "sonner";
import { apiGet } from "@/lib/api-client";
import { KpiCard } from "@/components/shared/kpi-card";
import { StatusBadge } from "@/components/shared/status-badge";
import type { Job } from "@/types/api";

// Paginated/list response shape from FastAPI
interface JobsListResponse {
  items?: Job[];
  total?: number;
}

function formatRelativeTime(dateStr: string): string {
  try {
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMin = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMin / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMin < 1) return "just now";
    if (diffMin < 60) return `${diffMin}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  } catch {
    return "";
  }
}

export default function DashboardPage() {
  // KPI: Active Jobs
  const activeJobsQuery = useQuery({
    queryKey: ["kpi", "jobs", "in_progress"],
    queryFn: () => apiGet<JobsListResponse | Job[]>("/api/v1/jobs?status=in_progress"),
    retry: 1,
  });

  // KPI: Pending Quotes
  const pendingQuotesQuery = useQuery({
    queryKey: ["kpi", "quotes", "draft"],
    queryFn: () => apiGet<{ total?: number; items?: unknown[] } | unknown[]>("/api/v1/quotes?status=draft"),
    retry: 1,
  });

  // KPI: Overdue Invoices
  const overdueInvoicesQuery = useQuery({
    queryKey: ["kpi", "invoices", "overdue"],
    queryFn: () => apiGet<{ total?: number; items?: unknown[] } | unknown[]>("/api/v1/invoices?status=overdue"),
    retry: 1,
  });

  // KPI: Today's Schedule
  const todayScheduleQuery = useQuery({
    queryKey: ["kpi", "schedule", "today"],
    queryFn: () => {
      const today = new Date().toISOString().split("T")[0];
      return apiGet<{ total?: number; items?: unknown[] } | unknown[]>(`/api/v1/scheduling/bookings?date=${today}`);
    },
    retry: 1,
  });

  // Recent activity: 10 most recently updated jobs
  const recentJobsQuery = useQuery({
    queryKey: ["dashboard", "recent-jobs"],
    queryFn: () => apiGet<JobsListResponse | Job[]>("/api/v1/jobs?limit=10&sort=-updated_at"),
    retry: 1,
  });

  // Show persistent error toasts if queries fail
  if (activeJobsQuery.isError) {
    toast.error("Failed to load dashboard data", { duration: Infinity });
  }

  // Helpers to extract counts from various response shapes
  function extractCount(data: unknown): number {
    if (data === null || data === undefined) return 0;
    if (typeof data === "object" && !Array.isArray(data)) {
      const d = data as Record<string, unknown>;
      if (typeof d.total === "number") return d.total;
      if (Array.isArray(d.items)) return d.items.length;
    }
    if (Array.isArray(data)) return data.length;
    return 0;
  }

  function extractJobs(data: unknown): Job[] {
    if (data === null || data === undefined) return [];
    if (Array.isArray(data)) return data as Job[];
    if (typeof data === "object") {
      const d = data as Record<string, unknown>;
      if (Array.isArray(d.items)) return d.items as Job[];
    }
    return [];
  }

  const activeJobsCount = extractCount(activeJobsQuery.data);
  const pendingQuotesCount = extractCount(pendingQuotesQuery.data);
  const overdueInvoicesCount = extractCount(overdueInvoicesQuery.data);
  const todayScheduleCount = extractCount(todayScheduleQuery.data);

  const recentJobs = extractJobs(recentJobsQuery.data);
  // Client-side sort by updated_at descending and slice to 10
  const sortedRecentJobs = [...recentJobs]
    .sort((a, b) => {
      const aTime = (a as Job & { updated_at?: string }).updated_at ?? "";
      const bTime = (b as Job & { updated_at?: string }).updated_at ?? "";
      return bTime.localeCompare(aTime);
    })
    .slice(0, 10);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Dashboard</h1>
        <p className="text-sm text-gray-500">Welcome back. Here&apos;s what&apos;s happening today.</p>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          title="Active Jobs"
          value={activeJobsCount}
          icon={Briefcase}
          href="/jobs"
          loading={activeJobsQuery.isLoading}
        />
        <KpiCard
          title="Pending Quotes"
          value={pendingQuotesCount}
          icon={FileText}
          href="/quotes"
          loading={pendingQuotesQuery.isLoading}
        />
        <KpiCard
          title="Overdue Invoices"
          value={overdueInvoicesCount}
          icon={Receipt}
          href="/invoices"
          loading={overdueInvoicesQuery.isLoading}
        />
        <KpiCard
          title="Today's Schedule"
          value={todayScheduleCount}
          icon={Calendar}
          href="/schedule"
          loading={todayScheduleQuery.isLoading}
        />
      </div>

      {/* Recent Activity */}
      <div className="rounded-xl bg-white ring-1 ring-foreground/10">
        <div className="border-b px-4 py-3">
          <h2 className="text-sm font-semibold text-gray-900">Recent Activity</h2>
          <p className="text-xs text-gray-500">Most recently updated jobs</p>
        </div>

        {recentJobsQuery.isLoading ? (
          <div className="divide-y">
            {[...Array(5)].map((_, i) => (
              <div key={i} className="flex items-center gap-4 px-4 py-3">
                <div className="h-4 w-48 animate-pulse rounded bg-gray-100" />
                <div className="h-5 w-16 animate-pulse rounded-full bg-gray-100" />
                <div className="ml-auto h-3 w-12 animate-pulse rounded bg-gray-100" />
              </div>
            ))}
          </div>
        ) : sortedRecentJobs.length === 0 ? (
          <div className="px-4 py-8 text-center text-sm text-gray-500">
            No jobs found. Jobs will appear here once created.
          </div>
        ) : (
          <ul className="divide-y">
            {sortedRecentJobs.map((job) => (
              <li key={job.id} className="flex items-center gap-4 px-4 py-3 hover:bg-gray-50">
                <span className="flex-1 truncate text-sm font-medium text-gray-900">
                  {job.title}
                </span>
                <StatusBadge status={job.status} size="sm" />
                {(job as Job & { updated_at?: string }).updated_at && (
                  <span className="ml-auto flex-shrink-0 text-xs text-gray-400">
                    {formatRelativeTime((job as Job & { updated_at?: string }).updated_at!)}
                  </span>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
