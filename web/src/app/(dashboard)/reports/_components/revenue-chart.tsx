"use client";

import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
} from "recharts";
import { useRouter } from "next/navigation";
import { type RevenueByMonthItem } from "@/types/api";

interface RevenueChartProps {
  data: RevenueByMonthItem[];
}

export function RevenueChart({ data }: RevenueChartProps) {
  const router = useRouter();

  const chartData = data.map((d) => ({
    month: d.month,
    paid: parseFloat(d.paid),
    unpaid: parseFloat(d.unpaid),
  }));

  return (
    <ResponsiveContainer width="100%" height={280}>
      <AreaChart
        data={chartData}
        margin={{ top: 4, right: 4, bottom: 0, left: 0 }}
        onClick={(e: Record<string, unknown>) => {
          const payload = e?.activePayload as Array<{ payload: { month: string } }> | undefined;
          if (payload?.[0]) {
            router.push(`/invoices?month=${payload[0].payload.month}`);
          }
        }}
        style={{ cursor: "pointer" }}
      >
        <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
        <XAxis dataKey="month" tick={{ fontSize: 11 }} tickLine={false} />
        <YAxis
          tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`}
          tick={{ fontSize: 11 }}
          tickLine={false}
          axisLine={false}
        />
        <Tooltip
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          formatter={(value: any, name: any) => {
            const v = typeof value === "string" ? parseFloat(value) : (value as number);
            return [
              `$${v.toLocaleString("en-AU", { minimumFractionDigits: 2 })}`,
              name === "paid" ? "Paid" : "Outstanding",
            ] as [string, string];
          }}
          contentStyle={{
            backgroundColor: "white",
            border: "1px solid var(--border)",
            borderRadius: "6px",
            boxShadow: "0 1px 2px rgba(0,0,0,0.05)",
            padding: "8px",
          }}
        />
        <Area
          type="monotone"
          dataKey="paid"
          stackId="1"
          stroke="#4f46e5"
          fill="#4f46e5"
          fillOpacity={0.25}
        />
        <Area
          type="monotone"
          dataKey="unpaid"
          stackId="1"
          stroke="#f59e0b"
          fill="#f59e0b"
          fillOpacity={0.25}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
