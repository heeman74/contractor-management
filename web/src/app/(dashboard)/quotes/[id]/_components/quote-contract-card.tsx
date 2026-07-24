"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowUpRight, Download, FileSignature, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/shared/status-badge";
import { downloadFileFromApi } from "@/lib/download-file";
import {
  useContractForQuote,
  useGenerateContract,
  useSendContract,
} from "@/lib/api/contracts";

interface QuoteContractCardProps {
  quoteId: string;
  clientName?: string | null;
}

export function QuoteContractCard({
  quoteId,
  clientName,
}: QuoteContractCardProps) {
  const { contract, isLoading } = useContractForQuote(quoteId);
  const generateContract = useGenerateContract();
  const sendContract = useSendContract();
  const [isDownloading, setDownloading] = useState(false);

  function handleCreate() {
    if (generateContract.isPending) return;
    generateContract.mutate(quoteId, {
      onSuccess: () => toast.success("Contract created. Review, then send it."),
      onError: () =>
        toast.error("Could not create the contract. Try again.", {
          duration: Infinity,
        }),
    });
  }

  function handleSend() {
    if (!contract || sendContract.isPending) return;
    sendContract.mutate(contract.id, {
      onSuccess: () =>
        toast.success(
          `Signature request sent to ${clientName ?? "the client"}.`
        ),
      onError: () =>
        toast.error("Could not send for signature. Try again.", {
          duration: Infinity,
        }),
    });
  }

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

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <FileSignature className="h-4 w-4 text-brand" />
          Contract
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {isLoading ? (
          <div className="h-16 animate-pulse rounded-lg bg-muted" />
        ) : !contract ? (
          <>
            <p className="text-sm text-muted-foreground">
              Turn this approved quote into a client contract for e-signature.
            </p>
            <Button
              variant="brand"
              size="sm"
              className="w-full"
              onClick={handleCreate}
              disabled={generateContract.isPending}
            >
              {generateContract.isPending && (
                <Loader2 className="h-4 w-4 animate-spin" />
              )}
              Create contract
            </Button>
          </>
        ) : (
          <>
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">Status</span>
              <StatusBadge status={contract.status} size="sm" />
            </div>

            {contract.status === "draft" && (
              <Button
                variant="brand"
                size="sm"
                className="w-full"
                onClick={handleSend}
                disabled={sendContract.isPending}
              >
                {sendContract.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
                Send for signature
              </Button>
            )}

            {(contract.status === "sent" || contract.status === "viewed") && (
              <p className="text-sm text-muted-foreground">
                Awaiting the client&apos;s signature. They received a secure
                signing link by email.
              </p>
            )}

            {contract.status === "declined" && (
              <p className="text-sm text-destructive">
                The client declined this contract.
              </p>
            )}

            {contract.status === "signed" && (
              <Button
                variant="outline"
                size="sm"
                className="w-full"
                onClick={handleDownloadSigned}
                disabled={isDownloading}
              >
                <Download className="h-4 w-4" />
                Download signed PDF
              </Button>
            )}

            <Link
              href={`/contracts/${contract.id}`}
              className="inline-flex items-center gap-1 text-xs font-medium text-brand hover:underline"
            >
              View contract
              <ArrowUpRight className="h-3.5 w-3.5" />
            </Link>
          </>
        )}
      </CardContent>
    </Card>
  );
}
