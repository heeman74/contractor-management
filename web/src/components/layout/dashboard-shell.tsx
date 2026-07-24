"use client";

import { useAppSelector } from "@/store/hooks";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { cn } from "@/lib/utils";

interface DashboardShellProps {
  children: React.ReactNode;
}

export function DashboardShell({ children }: DashboardShellProps) {
  const collapsed = useAppSelector((state) => state.ui.sidebarCollapsed);

  return (
    <div className="min-h-screen bg-background">
      {/* Desktop sidebar */}
      <Sidebar />

      {/* Main content area */}
      <div
        className={cn(
          "flex flex-col transition-all duration-300",
          // Desktop: offset by sidebar width
          collapsed ? "lg:ml-16" : "lg:ml-60"
        )}
      >
        <Topbar />
        <main className="flex-1 p-6">{children}</main>
      </div>
    </div>
  );
}
