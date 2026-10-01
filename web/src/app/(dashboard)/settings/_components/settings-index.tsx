"use client";

import Link from "next/link";
import { Building2, ShieldCheck, type LucideIcon } from "lucide-react";

import { usePermissions } from "@/lib/hooks/usePermissions";

/**
 * What this user can configure.
 *
 * Filtered by the same permissions that gate the pages themselves, so the hub
 * never offers a door that opens onto an empty room.
 */

interface SettingsSection {
  label: string;
  description: string;
  href: string;
  icon: LucideIcon;
  permission: string;
}

const SECTIONS: readonly SettingsSection[] = [
  {
    label: "Company profile",
    description:
      "Your details, licence number and the email your quotes are sent from.",
    href: "/settings/company",
    icon: Building2,
    permission: "company.settings.manage",
  },
  {
    label: "Roles & permissions",
    description: "What each role in your company is allowed to do.",
    href: "/settings/roles",
    icon: ShieldCheck,
    permission: "roles.permissions.manage",
  },
];

export function SettingsIndex() {
  const { can, isLoading } = usePermissions();

  if (isLoading) {
    return <div className="h-48 animate-pulse rounded-xl bg-muted" />;
  }

  const available = SECTIONS.filter((section) => can(section.permission));

  return (
    <div className="space-y-5">
      <div>
        <p className="eyebrow text-brand">Settings</p>
        <h1 className="font-display text-2xl font-bold tracking-tight text-foreground">
          Settings
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Configuration for your company.
        </p>
      </div>

      {available.length === 0 ? (
        <p className="rounded-xl bg-card px-5 py-5 text-sm text-muted-foreground ring-1 ring-foreground/10">
          You do not have access to any settings. An administrator at your
          company can change that.
        </p>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {available.map((section) => (
            <Link
              key={section.href}
              href={section.href}
              className="rounded-xl bg-card px-5 py-5 ring-1 ring-foreground/10 transition hover:ring-brand/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand"
            >
              <h2 className="flex items-center gap-2 font-display text-base font-bold tracking-tight text-foreground">
                <section.icon className="h-5 w-5" />
                {section.label}
              </h2>
              <p className="mt-1 text-sm text-muted-foreground">
                {section.description}
              </p>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
