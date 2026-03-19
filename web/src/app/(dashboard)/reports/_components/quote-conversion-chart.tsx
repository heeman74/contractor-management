"use client";

import {
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Tooltip,
  Legend,
} from "recharts";
import { useRouter } from "next/navigation";
import { type QuoteConversionItem } from "@/types/api";

interface QuoteConversionChartProps {
  data: QuoteConversionItem;
}

const COLORS: Record<string, string> = {
  approved: "#22c55e", // green-500
  declined: "#ef4444", // red-500
  pending: "#f59e0b",  // amber-500
};

export function QuoteConversionChart({ data }: QuoteConversionChartProps) {
  const router = useRouter();

  const pieData = [
    { name: "Approved", value: data.approved, key: "approved" },
    { name: "Declined", value: data.declined, key: "declined" },
    { name: "Pending", value: data.pending, key: "pending" },
  ].filter((d) => d.value > 0);

  const total = data.approved + data.declined + data.pending;

  return (
    <ResponsiveContainer width="100%" height={280}>
      <PieChart>
        <Pie
          data={pieData}
          dataKey="value"
          nameKey="name"
          cx="50%"
          cy="50%"
          outerRadius={90}
          label={({ name, percent }: { name?: string; percent?: number }) => `${name ?? ""} ${((percent ?? 0) * 100).toFixed(0)}%`}
          onClick={(_, index) => {
            const entry = pieData[index];
            if (entry) router.push(`/quotes?status=${entry.key}`);
          }}
          cursor="pointer"
        >
          {pieData.map((entry) => (
            <Cell key={entry.key} fill={COLORS[entry.key] || "#6b7280"} />
          ))}
        </Pie>
        <Tooltip
          contentStyle={{
            backgroundColor: "white",
            border: "1px solid var(--border)",
            borderRadius: "6px",
            boxShadow: "0 1px 2px rgba(0,0,0,0.05)",
            padding: "8px",
          }}
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          formatter={(value: any, name: any) => {
            const v = typeof value === "string" ? parseFloat(value) : (value as number);
            return [`${v} (${total > 0 ? ((v / total) * 100).toFixed(0) : 0}%)`, name] as [string, string];
          }}
        />
        <Legend />
      </PieChart>
    </ResponsiveContainer>
  );
}
