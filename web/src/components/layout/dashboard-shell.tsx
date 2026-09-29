"use client";

import { useAppSelector } from "@/store/hooks";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { cn } from "@/lib/utils";
import { useSessionBootstrap } from "@/features/auth/hooks/useSessionBootstrap";
import { useSessionWatchdog } from "@/features/auth/hooks/useSessionWatchdog";

interface DashboardShellProps {
  children: React.ReactNode;
}

export function DashboardShell({ children }: DashboardShellProps) {
  // A reload leaves the session cookie intact but empties Redux, so identity
  // and roles are recovered from the server rather than shown as a placeholder.
  useSessionBootstrap();

  // Returning to a tab whose session died sends the user to login rather than
  // leaving them reading data loaded before it expired.
  useSessionWatchdog();

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
