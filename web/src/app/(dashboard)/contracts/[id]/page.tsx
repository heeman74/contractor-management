"use client";

import { use, useState } from "react";
import Link from "next/link";
import { ArrowUpRight, Check, Download, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/shared/status-badge";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { useContract } from "@/lib/api/contracts";
import { downloadFileFromApi } from "@/lib/download-file";
import { formatDateTime } from "@/lib/format";
import type { Contract, ContractStatus } from "@/types/api";
import { cn } from "@/lib/utils";

// Happy-path lifecycle. declined/voided are terminal off-path states.
const LIFECYCLE: { status: ContractStatus; label: string }[] = [
  { status: "draft", label: "Created" },
  { status: "sent", label: "Sent for signature" },
  { status: "viewed", label: "Viewed by client" },
  { status: "signed", label: "Signed" },
];

function lifecycleIndex(status: ContractStatus): number {
  const index = LIFECYCLE.findIndex((step) => step.status === status);
  return index === -1 ? 0 : index;
}

function ContractTimeline({ contract }: { contract: Contract }) {
  const isTerminalOffPath =
    contract.status === "declined" || contract.status === "voided";
  const currentIndex = lifecycleIndex(contract.status);

  return (
    <ol className="space-y-4">
      {LIFECYCLE.map((step, index) => {
        const isDone = !isTerminalOffPath && index <= currentIndex;
        const isCurrent = !isTerminalOffPath && index === currentIndex;
        return (
          <li key={step.status} className="flex items-start gap-3">
            <span
              className={cn(
                "mt-0.5 flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full text-xs",
                isDone
                  ? "bg-brand text-brand-foreground"
                  : "bg-muted text-muted-foreground"
              )}
            >
              {isDone ? <Check className="h-3.5 w-3.5" /> : index + 1}
            </span>
            <div className="min-w-0">
              <p
                className={cn(
                  "text-sm",
                  isCurrent
                    ? "font-semibold text-foreground"
                    : isDone
                      ? "text-foreground"
                      : "text-muted-foreground"
                )}
              >
                {step.label}
              </p>
            </div>
          </li>
        );
      })}
      {isTerminalOffPath && (
        <li className="flex items-start gap-3">
          <span className="mt-0.5 flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full bg-destructive/15 text-destructive">
            <span className="text-xs font-bold">!</span>
          </span>
          <p className="text-sm font-semibold text-destructive">
            {contract.status === "declined" ? "Declined by client" : "Voided"}
          </p>
        </li>
      )}
    </ol>
  );
}

export default function ContractDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const { can, isLoading: permissionsLoading } = usePermissions();
  const { data: contract, isLoading, isError } = useContract(id);
  const [isDownloading, setDownloading] = useState(false);

  async function handleDownloadSigned() {
    if (!contract || isDownloading) return;
    setDownloading(true);
    const toastId = toast.loading("Downloading signed PDF...");
    try {
      await downloadFileFromApi(
        `/api/v1/contracts/${contract.id}/signed.pdf`,
        `contract-${contract.id}.pdf`
      );
      toast.dismiss(toastId);
    } catch {
      toast.dismiss(toastId);
      toast.error("Download failed. Try again.", { duration: Infinity });
    } finally {
      setDownloading(false);
    }
  }

  if (permissionsLoading || isLoading) {
    return <div className="h-64 animate-pulse rounded-xl bg-muted" />;
  }

  if (!can("contracts.manage")) {
    return (
      <div className="rounded-xl border border-yellow-200 bg-yellow-50 px-6 py-12 text-center">
        <p className="text-sm font-medium text-yellow-700">
          You do not have permission to view contracts.
        </p>
      </div>
    );
  }

  if (isError || !contract) {
    return (
      <div className="rounded-xl bg-card p-8 text-center ring-1 ring-foreground/10">
        <p className="text-sm text-muted-foreground">
          Failed to load contract. Check your connection and try again.
        </p>
      </div>
    );
  }

  const contractRef = `CT-${contract.id.slice(0, 6).toUpperCase()}`;

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <p className="eyebrow text-brand">Contract</p>
          <h1 className="flex flex-wrap items-center gap-2 font-display text-2xl font-bold tracking-tight text-foreground">
            <span className="num">{contractRef}</span>
            <StatusBadge status={contract.status} size="md" />
          </h1>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[1fr_340px]">
        {/* Main column */}
        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle>Signing status</CardTitle>
            </CardHeader>
            <CardContent>
              <ContractTimeline contract={contract} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Terms</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {contract.validity_statement && (
                <p className="rounded-lg border border-brand/40 bg-brand/10 px-3 py-2 text-xs text-foreground">
                  {contract.validity_statement}
                </p>
              )}
              <pre className="max-h-96 overflow-auto whitespace-pre-wrap rounded-lg border border-border bg-secondary/40 px-4 py-3 font-mono text-[0.75rem] leading-relaxed text-foreground">
                {contract.terms_snapshot}
              </pre>
            </CardContent>
          </Card>
        </div>

        {/* Sidebar column */}
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Actions</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {contract.status === "signed" && contract.signed_pdf_url ? (
                <Button
                  variant="brand"
                  size="sm"
                  className="w-full"
                  onClick={handleDownloadSigned}
                  disabled={isDownloading}
                >
                  {isDownloading ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <Download className="h-4 w-4" />
                  )}
                  Download signed PDF
                </Button>
              ) : (
                <p className="text-sm text-muted-foreground">
                  The signed PDF will be available here once the client signs.
                </p>
              )}
              <Link
                href={`/quotes/${contract.quote_id}`}
                className="inline-flex items-center gap-1 text-xs font-medium text-brand hover:underline"
              >
                View source quote
                <ArrowUpRight className="h-3.5 w-3.5" />
              </Link>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Details</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm">
              <DetailRow label="Signer" value={contract.signer_name} />
              <DetailRow label="Email" value={contract.signer_email} />
              <DetailRow
                label="Provider"
                value={contract.provider ?? "Not sent"}
              />
              <DetailRow
                label="Created"
                value={formatDateTime(contract.created_at)}
              />
              <DetailRow
                label="Updated"
                value={formatDateTime(contract.updated_at)}
              />
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}

function DetailRow({
  label,
  value,
}: {
  label: string;
  value: string | null;
}) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className="truncate text-right text-foreground">
        {value && value.trim() !== "" ? value : "—"}
      </span>
    </div>
  );
}
