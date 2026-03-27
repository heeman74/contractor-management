"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  LayoutDashboard,
  Briefcase,
  Calendar,
  FileText,
  FolderKanban,
  Receipt,
  Users,
  HardHat,
  BarChart3,
  Activity,
  ChevronLeft,
  ChevronRight,
  Menu,
  LogOut,
  UserCheck,
  ClipboardList,
} from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { cn } from "@/lib/utils";
import { useAppDispatch, useAppSelector } from "@/store/hooks";
import { toggleSidebar, setSidebarCollapsed } from "@/store/slices/ui-slice";
import { clearAuth } from "@/store/slices/auth-slice";
import { Separator } from "@/components/ui/separator";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";

import type { LucideIcon } from "lucide-react";

interface NavItem {
  label: string;
  href: string;
  icon: LucideIcon;
  /** If set, item only shows when user has at least one of these roles */
  roles?: string[];
}

const navItems: NavItem[] = [
  { label: "Dashboard", href: "/", icon: LayoutDashboard },
  { label: "Monitoring", href: "/monitoring", icon: Activity },
  { label: "Jobs", href: "/jobs", icon: Briefcase },
  { label: "Projects", href: "/projects", icon: FolderKanban },
  { label: "Schedule", href: "/schedule", icon: Calendar },
  { label: "Quotes", href: "/quotes", icon: FileText },
  { label: "Invoices", href: "/invoices", icon: Receipt },
  { label: "Clients", href: "/clients", icon: Users },
  { label: "Contractors", href: "/contractors", icon: HardHat },
  // Foreman section — role-gated
  { label: "Foreman Assignments", href: "/foreman", icon: UserCheck, roles: ["admin", "owner"] },
  { label: "My Projects", href: "/foreman/projects", icon: HardHat, roles: ["contractor"] },
  { label: "Daily Status", href: "/foreman/status", icon: ClipboardList, roles: ["contractor"] },
  { label: "Reports", href: "/reports", icon: BarChart3 },
];

interface SidebarNavProps {
  collapsed: boolean;
  displayName: string | null;
  roles: string[];
  onLogout: () => void;
  onToggle?: () => void;
}

function SidebarNav({ collapsed, displayName, roles, onLogout, onToggle }: SidebarNavProps) {
  const pathname = usePathname();

  const isActive = (href: string) => {
    if (href === "/") return pathname === "/";
    return pathname.startsWith(href);
  };

  // Filter nav items by role
  const visibleItems = navItems.filter((item) => {
    if (!item.roles) return true;
    return item.roles.some((r) => roles.includes(r));
  });

  return (
    <div className="flex h-full flex-col bg-gray-900 text-white">
      {/* Header with toggle */}
      <div className="flex h-14 items-center justify-between px-3">
        {!collapsed && (
          <span className="text-sm font-semibold text-indigo-300">ContractorHub</span>
        )}
        {onToggle && (
          <button
            onClick={onToggle}
            className={cn(
              "flex h-8 w-8 items-center justify-center rounded-md text-gray-400 hover:bg-gray-800 hover:text-white transition-colors",
              collapsed && "mx-auto"
            )}
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          >
            {collapsed ? (
              <ChevronRight className="h-4 w-4" />
            ) : (
              <ChevronLeft className="h-4 w-4" />
            )}
          </button>
        )}
      </div>

      {/* Navigation items */}
      <nav className="flex-1 space-y-1 px-2 py-2">
        {visibleItems.map(({ label, href, icon: Icon }) => (
          <Link
            key={href}
            href={href}
            className={cn(
              "flex items-center gap-3 rounded-md px-2 py-2 text-sm font-medium transition-colors",
              isActive(href)
                ? "bg-indigo-600 text-white"
                : "text-gray-300 hover:bg-gray-800 hover:text-white",
              collapsed && "justify-center px-0"
            )}
            title={collapsed ? label : undefined}
          >
            <Icon className="h-5 w-5 flex-shrink-0" />
            {!collapsed && <span>{label}</span>}
          </Link>
        ))}
      </nav>

      <Separator className="border-gray-700 bg-gray-700" />

      {/* Bottom: user section */}
      <div className="p-2">
        <div
          className={cn(
            "flex items-center gap-3 rounded-md px-2 py-2",
            collapsed && "justify-center px-0"
          )}
        >
          <Avatar className="flex-shrink-0 bg-indigo-600">
            <AvatarFallback className="bg-indigo-600 text-white text-xs">
              {displayName ? displayName.charAt(0).toUpperCase() : "U"}
            </AvatarFallback>
          </Avatar>
          {!collapsed && (
            <span className="flex-1 truncate text-xs text-gray-300">
              {displayName ?? "User"}
            </span>
          )}
          <button
            onClick={onLogout}
            className={cn(
              "flex items-center justify-center rounded-md p-1.5 text-gray-400 hover:bg-gray-800 hover:text-white transition-colors",
              collapsed && "mx-auto"
            )}
            title="Log out"
            aria-label="Log out"
          >
            <LogOut className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}

// Mobile hamburger button — exported for use in Topbar
interface MobileSidebarProps {
  displayName: string | null;
}

export function MobileSidebar({ displayName }: MobileSidebarProps) {
  const [open, setOpen] = useState(false);
  const dispatch = useAppDispatch();
  const router = useRouter();
  const queryClient = useQueryClient();
  const roles = useAppSelector((state) => state.auth.roles);

  const handleLogout = async () => {
    setOpen(false);
    try {
      await fetch("/api/auth/logout", { method: "POST" });
    } catch {
      // best-effort
    }
    queryClient.clear();
    dispatch(clearAuth());
    router.push("/login");
  };

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="flex items-center justify-center rounded-md p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-700 transition-colors lg:hidden"
        aria-label="Open menu"
      >
        <Menu className="h-5 w-5" />
      </button>

      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="left" className="p-0 w-[240px] bg-gray-900">
          <SheetHeader className="sr-only">
            <SheetTitle>Navigation</SheetTitle>
          </SheetHeader>
          <SidebarNav
            collapsed={false}
            displayName={displayName}
            roles={roles}
            onLogout={handleLogout}
          />
        </SheetContent>
      </Sheet>
    </>
  );
}

// Desktop sidebar
export function Sidebar() {
  const dispatch = useAppDispatch();
  const router = useRouter();
  const queryClient = useQueryClient();
  const collapsed = useAppSelector((state) => state.ui.sidebarCollapsed);
  const displayName = useAppSelector((state) => state.auth.displayName);
  const roles = useAppSelector((state) => state.auth.roles);

  // Hydrate sidebar state from localStorage on mount
  useEffect(() => {
    try {
      const stored = localStorage.getItem("sidebarCollapsed");
      if (stored !== null) {
        dispatch(setSidebarCollapsed(stored === "true"));
      }
    } catch {
      // ignore storage errors
    }
  }, [dispatch]);

  const handleToggle = () => {
    dispatch(toggleSidebar());
  };

  const handleLogout = async () => {
    try {
      await fetch("/api/auth/logout", { method: "POST" });
    } catch {
      // best-effort
    }
    queryClient.clear();
    dispatch(clearAuth());
    router.push("/login");
  };

  return (
    <>
      {/* Desktop sidebar — hidden on mobile */}
      <div
        className={cn(
          "fixed inset-y-0 left-0 z-40 hidden lg:flex flex-col transition-all duration-300",
          collapsed ? "w-16" : "w-60"
        )}
      >
        <SidebarNav
          collapsed={collapsed}
          displayName={displayName}
          roles={roles}
          onLogout={handleLogout}
          onToggle={handleToggle}
        />
      </div>
    </>
  );
}
