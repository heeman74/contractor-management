"use client";

import { use, useState } from "react";
import { StatusBadge } from "@/components/shared/status-badge";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDate } from "@/lib/format";
import { PageSkeleton } from "./_components/page-skeleton";
import { InvoiceLineItemsCard } from "./_components/invoice-line-items-card";
import { InvoicePaymentCard } from "./_components/invoice-payment-card";
import { InvoiceActionsCard } from "./_components/invoice-actions-card";
import { InvoiceDetailsCard } from "./_components/invoice-details-card";
import { PaymentSummary } from "./_components/payment-summary";
import { useInvoiceDetail } from "./_hooks/use-invoice-detail";

export default function InvoiceDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const detail = useInvoiceDetail(id);
  const [showPaymentForm, setShowPaymentForm] = useState(false);

  if (detail.isLoading) return <PageSkeleton />;

  if (detail.isError || !detail.invoice) {
    return (
      <div className="rounded-xl bg-white p-8 text-center ring-1 ring-foreground/10">
        <p className="text-sm text-gray-500">
          Failed to load invoice details. Check your connection and try again.
        </p>
      </div>
    );
  }

  const { invoice, job, balance, isOverdue } = detail;
  const computedStatus = isOverdue ? "overdue" : invoice.status;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-3 min-w-0">
          <h1 className="text-xl font-semibold text-gray-900">
            Invoice #{invoice.invoice_number}
          </h1>
          <StatusBadge status={computedStatus} size="md" />
        </div>
      </div>

      {isOverdue && (
        <Alert className="bg-red-50 border-l-4 border-red-400 text-red-800">
          <AlertDescription>
            This invoice is overdue. Due date: {formatDate(invoice.due_date)}.
          </AlertDescription>
        </Alert>
      )}

      {/* Two-column grid */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        {/* Main column */}
        <div className="space-y-6">
          <InvoiceLineItemsCard
            invoice={invoice}
            isFinalized={detail.isFinalized}
            editableItems={detail.editableItems}
            onUpdateItem={detail.updateLineItem}
            onSave={detail.saveLineItems}
            onFinalize={detail.finalize}
            isSaving={detail.isSaving}
            isFinalizing={detail.isFinalizing}
          />

          <InvoicePaymentCard
            invoice={invoice}
            balance={balance}
            isOverdue={isOverdue}
            isPaid={detail.isPaid}
            isRecordingPayment={detail.isRecordingPayment}
            showForm={showPaymentForm}
            onShowFormChange={setShowPaymentForm}
            onRecordPayment={detail.recordPayment}
          />
        </div>

        {/* Sidebar column */}
        <div className="space-y-4">
          <InvoiceActionsCard
            status={computedStatus}
            isPaid={detail.isPaid}
            isFinalized={detail.isFinalized}
            isRecordingPayment={detail.isRecordingPayment}
            isFinalizing={detail.isFinalizing}
            onRecordPayment={() => setShowPaymentForm(true)}
            onMarkFullyPaid={detail.markFullyPaid}
            onDownloadPdf={detail.downloadPdf}
            onFinalize={detail.finalize}
          />

          <Card>
            <CardHeader>
              <CardTitle>Payment Summary</CardTitle>
            </CardHeader>
            <CardContent>
              <PaymentSummary
                invoice={invoice}
                balance={balance}
                isOverdue={isOverdue}
                layout="stacked"
              />
            </CardContent>
          </Card>

          <InvoiceDetailsCard invoice={invoice} job={job} isOverdue={isOverdue} />
        </div>
      </div>
    </div>
  );
}
