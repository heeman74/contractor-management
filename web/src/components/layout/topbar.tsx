"use client";

import { usePathname, useRouter } from "next/navigation";
import Link from "next/link";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { useQueryClient } from "@tanstack/react-query";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { MobileSidebar } from "@/components/layout/sidebar";
import { useAppDispatch, useAppSelector } from "@/store/hooks";
import { clearAuth } from "@/store/slices/auth-slice";
import { LogOut, ChevronDown } from "lucide-react";

// Map path segments to human-readable labels
const SEGMENT_LABELS: Record<string, string> = {
  jobs: "Jobs",
  schedule: "Schedule",
  quotes: "Quotes",
  invoices: "Invoices",
  clients: "Clients",
  contractors: "Contractors",
  reports: "Reports",
  requests: "Requests",
  download: "Get Mobile App",
};

interface BreadcrumbSegment {
  label: string;
  href: string | null;
}

function buildBreadcrumbs(pathname: string): BreadcrumbSegment[] {
  const segments = pathname.split("/").filter(Boolean);

  if (segments.length === 0) {
    return [{ label: "Dashboard", href: null }];
  }

  const crumbs: BreadcrumbSegment[] = [{ label: "Dashboard", href: "/" }];

  segments.forEach((segment, index) => {
    const href = "/" + segments.slice(0, index + 1).join("/");
    const isLast = index === segments.length - 1;
    const label = SEGMENT_LABELS[segment] ?? segment.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
    crumbs.push({ label, href: isLast ? null : href });
  });

  return crumbs;
}

export function Topbar() {
  const pathname = usePathname();
  const router = useRouter();
  const dispatch = useAppDispatch();
  const displayName = useAppSelector((state) => state.auth.displayName);
  const companyName = useAppSelector((state) => state.auth.companyName);
  const pageTitle = useAppSelector((state) => state.ui.pageTitle);

  const queryClient = useQueryClient();

  const breadcrumbs = buildBreadcrumbs(pathname);

  // Override the last breadcrumb label with pageTitle when the segment is a UUID
  // (i.e., not a recognized SEGMENT_LABELS key — e.g., /jobs/abc123-uuid-...)
  if (pageTitle && breadcrumbs.length > 1) {
    const lastCrumb = breadcrumbs[breadcrumbs.length - 1];
    if (!lastCrumb.href && !SEGMENT_LABELS[pathname.split("/").filter(Boolean).pop() ?? ""]) {
      lastCrumb.label = pageTitle;
    }
  }

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

  const displayInitial = displayName ? displayName.charAt(0).toUpperCase() : "U";
  const displayLabel = companyName ?? displayName ?? "User";

  return (
    <header className="sticky top-0 z-30 flex h-14 items-center border-b bg-card px-4 gap-4">
      {/* Mobile hamburger */}
      <MobileSidebar displayName={displayName} />

      {/* Breadcrumbs */}
      <div className="flex-1 overflow-hidden">
        <Breadcrumb>
          <BreadcrumbList>
            {breadcrumbs.map((crumb, index) => (
              <span key={index} className="inline-flex items-center gap-1.5">
                {index > 0 && <BreadcrumbSeparator />}
                <BreadcrumbItem>
                  {crumb.href ? (
                    <BreadcrumbLink
                      render={
                        <Link href={crumb.href} className="transition-colors hover:text-foreground">
                          {crumb.label}
                        </Link>
                      }
                    />
                  ) : (
                    <BreadcrumbPage>{crumb.label}</BreadcrumbPage>
                  )}
                </BreadcrumbItem>
              </span>
            ))}
          </BreadcrumbList>
        </Breadcrumb>
      </div>

      {/* Right: company name + user dropdown */}
      <div className="flex items-center gap-2">
        {companyName && (
          <span className="hidden text-sm text-muted-foreground sm:inline">{companyName}</span>
        )}
        <DropdownMenu>
          <DropdownMenuTrigger className="flex items-center gap-2 rounded-md p-1 hover:bg-gray-100 transition-colors outline-none">
            <Avatar>
              <AvatarFallback className="bg-brand text-brand-foreground text-xs font-semibold">
                {displayInitial}
              </AvatarFallback>
            </Avatar>
            {!companyName && (
              <span className="hidden text-sm font-medium text-gray-700 sm:inline">
                {displayLabel}
              </span>
            )}
            <ChevronDown className="h-3 w-3 text-gray-400" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={handleLogout} className="cursor-pointer">
              <LogOut className="mr-2 h-4 w-4" />
              Log out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
