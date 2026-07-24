"use client";

import React from "react";
import { type LucideIcon, Download } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

interface ChartCardProps {
  title: string;
  kpiValue: string;
  icon: LucideIcon;
  csvFilename: string;
  csvRows: string[][];
  children: React.ReactNode;
  ariaLabel: string;
}

export function ChartCard({
  title,
  kpiValue,
  icon: Icon,
  csvFilename,
  csvRows,
  children,
  ariaLabel,
}: ChartCardProps) {
  function handleCsvDownload() {
    const content = csvRows.map((r) => r.map((c) => `"${c}"`).join(",")).join("\n");
    const blob = new Blob([content], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = csvFilename;
    link.click();
    URL.revokeObjectURL(url);
  }

  return (
    <Card aria-label={ariaLabel}>
      <CardContent className="pt-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-gray-500">{title}</p>
            <p className="mt-1 text-3xl font-bold text-gray-900">{kpiValue}</p>
          </div>
          <div className="flex items-center gap-2">
            <div className="rounded-md bg-secondary p-2">
              <Icon className="h-4 w-4 text-foreground/70" />
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={handleCsvDownload}
              aria-label={`Download ${title} as CSV`}
            >
              <Download className="h-4 w-4 mr-1" />
              Export CSV
            </Button>
          </div>
        </div>
        <div className="mt-4 min-h-[300px]">{children}</div>
      </CardContent>
    </Card>
  );
}
