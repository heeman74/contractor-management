"use client";

import { useState, useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { format, subDays } from "date-fns";
import { TrendingUp, Briefcase, PieChart as PieChartIcon } from "lucide-react";
import { toast } from "sonner";

import { apiGet } from "@/lib/api-client";
import { type DashboardResponse } from "@/types/api";

import { DateRangeFilter } from "./date-range-filter";
import { ChartCard } from "./chart-card";
import { RevenueChart } from "./revenue-chart";
import { JobsByStatusChart } from "./jobs-by-status-chart";
import { QuoteConversionChart } from "./quote-conversion-chart";
import { ReportsSkeleton } from "./reports-skeleton";

function EmptyState() {
  return (
    <div className="flex flex-col items-center justify-center py-16" role="status">
      <p className="text-sm font-medium text-muted-foreground">No data for this period</p>
      <p className="mt-1 text-sm text-muted-foreground">
        Try a wider date range or check that data has been recorded for this period.
      </p>
    </div>
  );
}

export default function ReportsDashboard() {
  const [dateRange, setDateRange] = useState<{ from: Date; to: Date }>(() => ({
    from: subDays(new Date(), 30),
    to: new Date(),
  }));

  const startDate = format(dateRange.from, "yyyy-MM-dd");
  const endDate = format(dateRange.to, "yyyy-MM-dd");

  const { data, isLoading, isError } = useQuery({
    queryKey: ["reports", "dashboard", startDate, endDate],
    queryFn: () =>
      apiGet<DashboardResponse>(
        `/api/v1/reports/dashboard?start_date=${startDate}&end_date=${endDate}`
      ),
    retry: 1,
  });

  useEffect(() => {
    if (isError) toast.error("Failed to load reports.", { duration: Infinity });
  }, [isError]);

  // KPI computations
  const revenueTotal = data?.revenue_by_month.reduce(
    (sum, item) => sum + parseFloat(item.paid) + parseFloat(item.unpaid),
    0
  ) ?? 0;
  const revenueKpi = `$${revenueTotal.toLocaleString("en-AU", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })} total revenue`;

  const jobsTotal = data?.jobs_by_status.reduce((sum, item) => sum + item.count, 0) ?? 0;
  const jobsKpi = `${jobsTotal} total jobs`;

  const quoteKpi = data?.quote_conversion
    ? `${data.quote_conversion.conversion_rate}% approval rate`
    : "0% approval rate";

  // Empty state checks
  const revenueEmpty = !data?.revenue_by_month?.length;
  const jobsEmpty = !data?.jobs_by_status?.length;
  const quoteEmpty =
    (data?.quote_conversion.approved ?? 0) +
      (data?.quote_conversion.declined ?? 0) +
      (data?.quote_conversion.pending ?? 0) ===
    0;

  // CSV row builders
  const revenueCsvRows: string[][] = data
    ? [
        ["Month", "Paid", "Unpaid"],
        ...data.revenue_by_month.map((r) => [r.month, r.paid, r.unpaid]),
      ]
    : [["Month", "Paid", "Unpaid"]];

  const jobsCsvRows: string[][] = data
    ? [
        ["Status", "Count"],
        ...data.jobs_by_status.map((r) => [r.status, String(r.count)]),
      ]
    : [["Status", "Count"]];

  const quoteCsvRows: string[][] = data
    ? [
        ["Category", "Count"],
        ["Approved", String(data.quote_conversion.approved)],
        ["Declined", String(data.quote_conversion.declined)],
        ["Pending", String(data.quote_conversion.pending)],
      ]
    : [["Category", "Count"]];

  return (
    <div className="space-y-6">
      <DateRangeFilter dateRange={dateRange} onDateRangeChange={setDateRange} />
      {isLoading ? (
        <ReportsSkeleton />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          {/* Top row */}
          <ChartCard
            title="Revenue by Month"
            kpiValue={revenueKpi}
            icon={TrendingUp}
            csvFilename={`revenue-${startDate}-to-${endDate}.csv`}
            csvRows={revenueCsvRows}
            ariaLabel="Revenue by Month chart"
          >
            {revenueEmpty ? <EmptyState /> : <RevenueChart data={data!.revenue_by_month} />}
          </ChartCard>
          <ChartCard
            title="Jobs by Status"
            kpiValue={jobsKpi}
            icon={Briefcase}
            csvFilename={`jobs-by-status-${startDate}-to-${endDate}.csv`}
            csvRows={jobsCsvRows}
            ariaLabel="Jobs by Status chart"
          >
            {jobsEmpty ? <EmptyState /> : <JobsByStatusChart data={data!.jobs_by_status} />}
          </ChartCard>
          {/* Bottom row — utilization heatmap placeholder + quote conversion */}
          <div>{/* Placeholder for utilization heatmap — Plan 03 */}</div>
          <ChartCard
            title="Quote Conversion"
            kpiValue={quoteKpi}
            icon={PieChartIcon}
            csvFilename={`quote-conversion-${startDate}-to-${endDate}.csv`}
            csvRows={quoteCsvRows}
            ariaLabel="Quote Conversion chart"
          >
            {quoteEmpty ? (
              <EmptyState />
            ) : (
              <QuoteConversionChart data={data!.quote_conversion} />
            )}
          </ChartCard>
        </div>
      )}
    </div>
  );
}
