"use client";

import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  Cell,
} from "recharts";
import { useRouter } from "next/navigation";
import { type JobsByStatusItem } from "@/types/api";

interface JobsByStatusChartProps {
  data: JobsByStatusItem[];
}

const STATUS_COLORS: Record<string, string> = {
  quote: "#6366f1",       // indigo-500
  scheduled: "#3b82f6",   // blue-500
  in_progress: "#f59e0b", // amber-500
  complete: "#22c55e",    // green-500
  invoiced: "#8b5cf6",    // violet-500
  cancelled: "#6b7280",   // gray-500
};

export function JobsByStatusChart({ data }: JobsByStatusChartProps) {
  const router = useRouter();

  return (
    <ResponsiveContainer width="100%" height={280}>
      <BarChart data={data} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
        <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
        <XAxis
          dataKey="status"
          tick={{ fontSize: 11 }}
          tickLine={false}
          tickFormatter={(v) => v.replace("_", " ")}
        />
        <YAxis
          tick={{ fontSize: 11 }}
          tickLine={false}
          axisLine={false}
          allowDecimals={false}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: "white",
            border: "1px solid var(--border)",
            borderRadius: "6px",
            boxShadow: "0 1px 2px rgba(0,0,0,0.05)",
            padding: "8px",
          }}
        />
        <Bar
          dataKey="count"
          cursor="pointer"
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          onClick={(barData: any) => router.push(`/jobs?status=${(barData as JobsByStatusItem).status}`)}
        >
          {data.map((entry, index) => (
            <Cell key={index} fill={STATUS_COLORS[entry.status] || "#6b7280"} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
