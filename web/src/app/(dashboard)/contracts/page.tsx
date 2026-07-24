"use client";

import Link from "next/link";
import { FileSignature } from "lucide-react";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { StatusBadge } from "@/components/shared/status-badge";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { useContracts } from "@/lib/api/contracts";
import { formatDate } from "@/lib/format";
import type { Contract } from "@/types/api";

function contractRef(id: string) {
  return `CT-${id.slice(0, 6).toUpperCase()}`;
}

export default function ContractsPage() {
  const { can, isLoading: permissionsLoading } = usePermissions();
  const { data: contracts, isLoading, isError } = useContracts();

  if (permissionsLoading) {
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

  return (
    <div className="space-y-6">
      <div>
        <p className="eyebrow text-brand">Agreements</p>
        <h1 className="flex items-center gap-2 font-display text-2xl font-bold tracking-tight text-foreground">
          <FileSignature className="h-6 w-6" />
          Contracts
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Client contracts generated from approved quotes and their signing
          status.
        </p>
      </div>

      <div className="overflow-hidden rounded-xl bg-card ring-1 ring-foreground/10">
        {isLoading ? (
          <div className="h-48 animate-pulse bg-muted" />
        ) : isError ? (
          <p className="px-5 py-8 text-center text-sm text-destructive">
            Could not load contracts. Refresh to try again.
          </p>
        ) : !contracts || contracts.length === 0 ? (
          <div className="px-5 py-12 text-center">
            <p className="text-sm text-muted-foreground">
              No contracts yet. Approve a quote, then create a contract from it.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Contract</TableHead>
                  <TableHead>Signer</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Created</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {contracts.map((contract: Contract) => (
                  <TableRow key={contract.id} className="cursor-pointer">
                    <TableCell className="font-medium">
                      <Link
                        href={`/contracts/${contract.id}`}
                        className="num text-foreground hover:text-brand hover:underline"
                      >
                        {contractRef(contract.id)}
                      </Link>
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {contract.signer_name ?? "—"}
                    </TableCell>
                    <TableCell>
                      <StatusBadge status={contract.status} size="sm" />
                    </TableCell>
                    <TableCell className="num text-muted-foreground">
                      {formatDate(contract.created_at)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </div>
    </div>
  );
}
