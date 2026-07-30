"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import { PageSkeleton } from "./_components/page-skeleton";
import { QuoteStatusAlerts } from "./_components/quote-status-alerts";
import { QuoteLineItemsCard } from "./_components/quote-line-items-card";
import { QuoteActivityCard } from "./_components/quote-activity-card";
import { QuoteActionsCard } from "./_components/quote-actions-card";
import { QuoteContractCard } from "./_components/quote-contract-card";
import { QuoteDetailsCard } from "./_components/quote-details-card";
import { QuoteFinancialSummary } from "./_components/quote-financial-summary";
import { QuoteVarianceSection } from "./_components/quote-variance-section";
import { LinkedInvoiceCard } from "./_components/linked-invoice-card";
import { FinanceGate } from "@/features/finance/components/FinanceGate";
import { SendQuoteDialog, ExtendExpiryDialog } from "./_components/quote-dialogs";
import { useQuoteDetail } from "./_hooks/use-quote-detail";
import { buildQuoteActivity } from "./_lib/quote-activity";

export default function QuoteDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const router = useRouter();
  const searchParams = useSearchParams();
  const detail = useQuoteDetail(id);

  const [sendOpen, setSendOpen] = useState(false);
  const [extendOpen, setExtendOpen] = useState(false);

  // "new" is the create sentinel — the bare detail route can't load a quote
  // called "new". Send the user into the editor, preserving any job_id param.
  const isNew = id === "new";
  useEffect(() => {
    if (!isNew) return;
    const query = searchParams.toString();
    router.replace(`/quotes/new/edit${query ? `?${query}` : ""}`);
  }, [isNew, searchParams, router]);

  if (isNew || detail.isLoading) return <PageSkeleton />;

  if (detail.isError || !detail.quote) {
    return (
      <div className="rounded-xl bg-white p-8 text-center ring-1 ring-foreground/10">
        <p className="text-sm text-gray-500">
          Failed to load quote. Check your connection and try again.
        </p>
      </div>
    );
  }

  const { quote, job } = detail;
  const activity = buildQuoteActivity(quote);

  function sendQuote() {
    detail.sendQuote();
    setSendOpen(false);
  }

  function extendExpiry(date: string) {
    detail.extendExpiry(date);
    setExtendOpen(false);
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold text-gray-900 truncate flex items-center gap-2 flex-wrap">
            {`Quote #${detail.quoteRef}`}
            {job?.description && (
              <span className="text-gray-400 font-normal">
                — {job.description}
              </span>
            )}
            <StatusBadge status={quote.status} size="md" />
          </h1>
          {quote.revision_number > 1 && (
            <span className="mt-1 inline-flex items-center rounded-full border border-gray-300 px-2 py-0.5 text-xs text-gray-600">
              v{quote.revision_number}
            </span>
          )}
        </div>
      </div>

      <QuoteStatusAlerts
        quote={quote}
        onRevise={detail.goToRevise}
        onExtendExpiry={() => setExtendOpen(true)}
      />

      {/* Two-column grid */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        {/* Main column */}
        <div className="space-y-6">
          <QuoteLineItemsCard quote={quote} />

          <Card>
            <CardHeader>
              <CardTitle>Admin Notes</CardTitle>
            </CardHeader>
            <CardContent>
              {quote.admin_notes ? (
                <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-wrap">
                  {quote.admin_notes}
                </p>
              ) : (
                <p className="text-sm text-gray-400 italic">No notes</p>
              )}
            </CardContent>
          </Card>

          <QuoteActivityCard events={activity} />
        </div>

        {/* Sidebar column */}
        <div className="space-y-4">
          <QuoteActionsCard
            quote={quote}
            job={job}
            isPdfDownloading={detail.isPdfDownloading}
            isSending={detail.isSending}
            isGeneratingInvoice={detail.isGeneratingInvoice}
            onSend={() => setSendOpen(true)}
            onEdit={detail.goToEdit}
            onRevise={detail.goToRevise}
            onExtendExpiry={() => setExtendOpen(true)}
            onDownloadPdf={detail.downloadPdf}
            onGenerateInvoice={detail.generateInvoice}
          />

          {quote.project_id && (
            <Card>
              <CardHeader>
                <CardTitle>Project</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                <p className="text-sm text-gray-600">
                  This quote was approved and turned into a project.
                </p>
                <Link
                  href={`/projects?project=${quote.project_id}`}
                  className="inline-flex items-center gap-1 text-sm font-medium text-brand hover:underline"
                >
                  View project →
                </Link>
              </CardContent>
            </Card>
          )}

          {quote.status === "approved" && (
            <QuoteContractCard quoteId={quote.id} clientName={job?.client_name} />
          )}

          <QuoteDetailsCard quote={quote} job={job} />

          <Card>
            <CardHeader>
              <CardTitle>Financial Summary</CardTitle>
            </CardHeader>
            <CardContent>
              <QuoteFinancialSummary quote={quote} emphasizeTotal />
            </CardContent>
          </Card>

          {/* Trap 8 double lock: FinanceGate stops the render, and the
              variance section's own hook-level enabled flag (a child of the
              gate, never a sibling) stops the request. The fallback below is
              null because a sidebar card the viewer may not be entitled to
              must never reserve layout, flash a skeleton or announce its own
              absence with a deny panel on a page they otherwise own. The page
              owns no variance hook — that is the entire purpose of the
              section container below. */}
          <FinanceGate fallback={null}>
            <QuoteVarianceSection
              quoteId={quote.id}
              isApproved={quote.status === "approved"}
            />
          </FinanceGate>

          {detail.linkedInvoice && (
            <LinkedInvoiceCard invoice={detail.linkedInvoice} />
          )}
        </div>
      </div>

      <SendQuoteDialog
        open={sendOpen}
        onOpenChange={setSendOpen}
        clientName={job?.client_name ?? "client"}
        isSending={detail.isSending}
        onConfirm={sendQuote}
      />
      <ExtendExpiryDialog
        open={extendOpen}
        onOpenChange={setExtendOpen}
        isExtending={detail.isExtending}
        onConfirm={extendExpiry}
      />
    </div>
  );
}
