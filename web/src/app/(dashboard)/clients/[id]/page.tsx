"use client";

import { useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import {
  ChevronDown,
  ChevronRight,
  Star,
  ArrowLeft,
} from "lucide-react";
import { apiGet } from "@/lib/api-client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { StatusBadge } from "@/components/shared/status-badge";
import type { ClientDetail, ClientProperty } from "@/types/api";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString();
}

// ---------------------------------------------------------------------------
// Property row with expand/collapse
// ---------------------------------------------------------------------------

function PropertyRow({ property }: { property: ClientProperty }) {
  const [expanded, setExpanded] = useState(false);

  const label = property.nickname ?? "Property";
  const addressParts = [
    property.address_line1,
    property.city,
    property.state,
    property.postal_code,
  ]
    .filter(Boolean)
    .join(", ");

  return (
    <div className="border-b last:border-b-0">
      <button
        type="button"
        className="w-full flex items-center justify-between px-4 py-3 text-left hover:bg-muted/50 transition-colors"
        onClick={() => setExpanded((v) => !v)}
      >
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-gray-900">{label}</span>
          {property.is_default && (
            <Badge className="bg-secondary text-foreground text-xs">Default</Badge>
          )}
        </div>
        {expanded ? (
          <ChevronDown className="h-4 w-4 text-gray-400" />
        ) : (
          <ChevronRight className="h-4 w-4 text-gray-400" />
        )}
      </button>
      {expanded && addressParts && (
        <div className="px-4 pb-3 text-sm text-muted-foreground">{addressParts}</div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Sidebar info row
// ---------------------------------------------------------------------------

function InfoRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="text-xs font-medium text-gray-500 uppercase tracking-wide">
        {label}
      </span>
      <div className="text-sm text-gray-900">{children}</div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

function LoadingSkeleton() {
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <Skeleton className="h-8 w-48" />
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        <div className="space-y-6">
          <Skeleton className="h-64 w-full rounded-xl" />
          <Skeleton className="h-48 w-full rounded-xl" />
        </div>
        <div className="space-y-4">
          <Skeleton className="h-40 w-full rounded-xl" />
          <Skeleton className="h-24 w-full rounded-xl" />
          <Skeleton className="h-24 w-full rounded-xl" />
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function ClientDetailPage() {
  const params = useParams();
  const router = useRouter();
  const clientId = params.id as string;

  const { data: client, isLoading, isError } = useQuery({
    queryKey: ["client-detail", clientId],
    queryFn: () => apiGet<ClientDetail>(`/api/v1/crm/clients/${clientId}`),
    enabled: !!clientId,
  });

  if (isLoading) {
    return <LoadingSkeleton />;
  }

  if (isError || !client) {
    return (
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <p className="text-center py-12 text-muted-foreground">
          Failed to load client profile. Please refresh the page.
        </p>
      </div>
    );
  }

  const fullName = [client.first_name, client.last_name].filter(Boolean).join(" ") || client.email;

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* Page header */}
      <div className="space-y-1">
        <Link
          href="/clients"
          className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-gray-900 transition-colors"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to Clients
        </Link>
        <h1 className="text-2xl font-bold leading-tight">{fullName}</h1>
      </div>

      {/* Two-column layout */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        {/* ---------------------------------------------------------------- */}
        {/* Main column                                                       */}
        {/* ---------------------------------------------------------------- */}
        <div className="space-y-6">
          {/* Job History */}
          <Card>
            <CardHeader>
              <CardTitle>Job History</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {client.jobs.length === 0 ? (
                <p className="px-6 py-8 text-center text-sm text-muted-foreground">
                  No jobs found for this client.
                </p>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Job #
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Title
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Status
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Contractor
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Date
                      </TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {client.jobs.map((job) => (
                      <TableRow
                        key={job.id}
                        className="cursor-pointer hover:bg-muted/50"
                        onClick={() => router.push(`/jobs/${job.id}`)}
                      >
                        <TableCell className="py-3 px-4 font-mono text-sm text-gray-900">
                          {job.id.slice(0, 8).toUpperCase()}
                        </TableCell>
                        <TableCell className="py-3 px-4 text-sm text-gray-700 truncate max-w-xs">
                          {job.description}
                        </TableCell>
                        <TableCell className="py-3 px-4">
                          <StatusBadge status={job.status} size="sm" />
                        </TableCell>
                        <TableCell className="py-3 px-4 text-sm text-gray-500">
                          {job.client_name ?? "—"}
                        </TableCell>
                        <TableCell className="py-3 px-4 text-sm text-gray-500">
                          {formatDate(job.created_at)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          {/* Saved Properties */}
          <Card>
            <CardHeader>
              <CardTitle>Saved Properties</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {client.properties.length === 0 ? (
                <p className="px-6 py-8 text-center text-sm text-muted-foreground">
                  No saved properties.
                </p>
              ) : (
                <div>
                  {client.properties.map((property) => (
                    <PropertyRow key={property.id} property={property} />
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        {/* ---------------------------------------------------------------- */}
        {/* Sidebar                                                           */}
        {/* ---------------------------------------------------------------- */}
        <div className="space-y-4">
          {/* Contact card */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">{fullName}</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <Separator />
              <InfoRow label="Email">
                <a
                  href={`mailto:${client.email}`}
                  className="text-foreground hover:underline"
                >
                  {client.email}
                </a>
              </InfoRow>
              {client.phone && (
                <InfoRow label="Phone">{client.phone}</InfoRow>
              )}
              {client.preferred_contact_method && (
                <InfoRow label="Preferred Contact">{client.preferred_contact_method}</InfoRow>
              )}
            </CardContent>
          </Card>

          {/* Tags card */}
          {client.tags.length > 0 && (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Tags</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-1">
                  {client.tags.map((tag) => (
                    <span
                      key={tag}
                      className="bg-secondary text-foreground text-xs rounded-full px-2 py-0.5"
                    >
                      {tag}
                    </span>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}

          {/* Average Rating */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Average Rating</CardTitle>
            </CardHeader>
            <CardContent>
              {client.average_rating ? (
                <div className="flex items-center gap-1 text-sm text-gray-900">
                  <Star className="h-4 w-4 text-yellow-400 fill-yellow-400" />
                  <span>{client.average_rating}</span>
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">No ratings yet</p>
              )}
            </CardContent>
          </Card>

          {/* Referral Source */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Referral Source</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm text-gray-900">
                {client.referral_source ?? "Not specified"}
              </p>
            </CardContent>
          </Card>

          {/* Preferred Contractor */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Preferred Contractor</CardTitle>
            </CardHeader>
            <CardContent>
              {client.preferred_contractor_id && client.preferred_contractor_name ? (
                <Link
                  href={`/contractors/${client.preferred_contractor_id}`}
                  className="text-sm text-foreground hover:underline"
                >
                  {client.preferred_contractor_name}
                </Link>
              ) : (
                <p className="text-sm text-muted-foreground">None assigned</p>
              )}
            </CardContent>
          </Card>

          {/* Billing Address */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Billing Address</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm text-gray-900">
                {client.billing_address ?? "Not set"}
              </p>
            </CardContent>
          </Card>

          {/* Admin Notes */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Admin Notes</CardTitle>
            </CardHeader>
            <CardContent>
              {client.admin_notes ? (
                <p className="text-sm text-muted-foreground whitespace-pre-wrap">
                  {client.admin_notes}
                </p>
              ) : (
                <p className="text-sm text-muted-foreground">
                  No notes have been added for this client.
                </p>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
