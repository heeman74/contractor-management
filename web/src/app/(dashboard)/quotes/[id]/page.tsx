"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet, apiPost, apiFetchRaw } from "@/lib/api-client";
import type { Quote, Job, Invoice } from "@/types/api";
import { StatusBadge } from "@/components/shared/status-badge";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

// ---------------------------------------------------------------------------
// Skeleton
// ---------------------------------------------------------------------------

function PageSkeleton() {
  return (
    <div className="space-y-6 animate-pulse">
      <div className="space-y-2">
        <div className="h-7 w-2/3 rounded bg-gray-200" />
        <div className="h-5 w-24 rounded-full bg-gray-200" />
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        <div className="space-y-6">
          <div className="rounded-xl bg-gray-100 h-48" />
          <div className="rounded-xl bg-gray-100 h-24" />
          <div className="rounded-xl bg-gray-100 h-32" />
        </div>
        <div className="space-y-4">
          <div className="rounded-xl bg-gray-100 h-40" />
          <div className="rounded-xl bg-gray-100 h-32" />
          <div className="rounded-xl bg-gray-100 h-36" />
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Status stepper helper
// ---------------------------------------------------------------------------

const STEPPER_STEPS = ["draft", "sent", "viewed", "approved"];

function StatusStepper({ currentStatus }: { currentStatus: string }) {
  const currentIdx = STEPPER_STEPS.indexOf(currentStatus);
  const isDeclined = currentStatus === "declined";
  const isExpired = currentStatus === "expired";

  return (
    <div className="flex items-center flex-wrap gap-1">
      {STEPPER_STEPS.map((step, idx) => {
        let cls =
          "rounded-full px-2 py-0.5 text-xs bg-gray-100 text-gray-400";
        if (isDeclined || isExpired) {
          if (idx < currentIdx || (currentIdx === -1 && idx <= 2)) {
            cls = "rounded-full px-2 py-0.5 text-xs bg-indigo-600 text-white";
          }
        } else if (idx < currentIdx) {
          cls = "rounded-full px-2 py-0.5 text-xs bg-indigo-600 text-white";
        } else if (idx === currentIdx) {
          cls =
            "rounded-full px-2 py-0.5 text-xs bg-indigo-100 text-indigo-800 font-semibold";
        }
        return (
          <span key={step} className="flex items-center">
            <span className={cls}>
              {step.charAt(0).toUpperCase() + step.slice(1)}
            </span>
            {idx < STEPPER_STEPS.length - 1 && (
              <span className="text-xs text-gray-300 mx-1">{"→"}</span>
            )}
          </span>
        );
      })}
      {(isDeclined || isExpired) && (
        <>
          <span className="text-xs text-gray-300 mx-1">/</span>
          <span className="rounded-full px-2 py-0.5 text-xs bg-indigo-100 text-indigo-800 font-semibold">
            {currentStatus.charAt(0).toUpperCase() + currentStatus.slice(1)}
          </span>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function QuoteDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const router = useRouter();
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

  const [sendDialogOpen, setSendDialogOpen] = useState(false);
  const [extendDialogOpen, setExtendDialogOpen] = useState(false);
  const [newExpiryDate, setNewExpiryDate] = useState("");
  const [pdfDownloading, setPdfDownloading] = useState(false);

  // --- Queries ---
  const {
    data: quote,
    isLoading,
    isError,
  } = useQuery<Quote>({
    queryKey: ["quote", id],
    queryFn: () => apiGet<Quote>(`/api/v1/quotes/${id}`),
  });

  const { data: job } = useQuery<Job>({
    queryKey: ["job", quote?.job_id],
    queryFn: () => apiGet<Job>(`/api/v1/jobs/${quote!.job_id}`),
    enabled: !!quote?.job_id,
  });

  const { data: linkedInvoice } = useQuery<Invoice | null>({
    queryKey: ["invoice-for-job", quote?.job_id],
    queryFn: () =>
      apiGet<Invoice>(`/api/v1/invoices/for-job/${quote!.job_id}`).catch(
        () => null
      ),
    enabled: !!quote?.job_id && quote?.status === "approved",
  });

  // --- Breadcrumb title ---
  useEffect(() => {
    if (quote) {
      dispatch(
        setPageTitle(`Quote #QT-${id.slice(0, 6).toUpperCase()}`)
      );
    }
    return () => {
      dispatch(setPageTitle(null));
    };
  }, [quote, id, dispatch]);

  useEffect(() => {
    if (isError) {
      toast.error("Failed to load quote. Check your connection and try again.", {
        duration: Infinity,
      });
    }
  }, [isError]);

  // --- Mutations ---
  const sendMutation = useMutation<Quote, Error, void>({
    mutationFn: () => apiPost<Quote>(`/api/v1/quotes/${id}/send`, {}),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["quote", id] });
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      setSendDialogOpen(false);
      toast.success(
        "Quote sent to " + (job?.client_name ?? "client")
      );
    },
    onError: () => {
      toast.error("Failed to send quote. Try again.", { duration: Infinity });
    },
  });

  const extendMutation = useMutation<Quote, Error, string>({
    mutationFn: (newDate: string) =>
      apiPost<Quote>(`/api/v1/quotes/${id}/extend`, {
        new_expiry_date: newDate,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["quote", id] });
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      setExtendDialogOpen(false);
      setNewExpiryDate("");
      toast.success("Expiry date extended successfully.");
    },
    onError: () => {
      toast.error("Failed to extend expiry. Try again.", {
        duration: Infinity,
      });
    },
  });

  const generateInvoiceMutation = useMutation<Invoice, Error, void>({
    mutationFn: () =>
      apiPost<Invoice>(`/api/v1/invoices/generate/${quote!.job_id}`, {}),
    onSuccess: (invoice) => {
      toast.success(
        `Invoice #${invoice.invoice_number} generated`
      );
      router.push(`/invoices/${invoice.id}`);
    },
    onError: () => {
      toast.error("Failed to generate invoice. Try again.", {
        duration: Infinity,
      });
    },
  });

  // --- PDF Download ---
  async function handleDownloadPdf() {
    if (pdfDownloading) return;
    setPdfDownloading(true);
    const toastId = toast.loading("Downloading PDF...");
    try {
      const resp = await apiFetchRaw(`/api/v1/quotes/${id}/pdf`);
      const blob = await resp.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `quote-${id}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
      toast.dismiss(toastId);
    } catch {
      toast.dismiss(toastId);
      toast.error("PDF download failed. Try again.", { duration: Infinity });
    } finally {
      setPdfDownloading(false);
    }
  }

  // --- Loading / error states ---
  if (isLoading) return <PageSkeleton />;

  if (isError || !quote) {
    return (
      <div className="rounded-xl bg-white p-8 text-center ring-1 ring-foreground/10">
        <p className="text-sm text-gray-500">
          Failed to load quote. Check your connection and try again.
        </p>
      </div>
    );
  }

  // --- Derived values ---
  const quoteRef = `QT-${id.slice(0, 6).toUpperCase()}`;

  const activityEvents = [
    { label: "Created", date: quote.created_at, status: "draft" },
    quote.sent_at
      ? { label: "Sent to client", date: quote.sent_at, status: "sent" }
      : null,
    quote.viewed_at
      ? { label: "Viewed by client", date: quote.viewed_at, status: "viewed" }
      : null,
    quote.approved_at
      ? {
          label: "Approved by client",
          date: quote.approved_at,
          status: "approved",
        }
      : null,
    quote.declined_at
      ? {
          label: "Declined by client",
          date: quote.declined_at,
          status: "declined",
        }
      : null,
  ].filter(Boolean) as Array<{ label: string; date: string; status: string }>;

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold text-gray-900 truncate flex items-center gap-2 flex-wrap">
            {`Quote #${quoteRef}`}
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

      {/* Alert banners for declined/expired */}
      {quote.status === "declined" && (
        <Alert className="bg-red-50 border-l-4 border-red-400 text-red-800">
          <AlertDescription className="text-red-800">
            <div className="flex items-start justify-between gap-4 flex-wrap">
              <div>
                <strong>Declined by client</strong>
                {quote.decline_reason && (
                  <span>: {quote.decline_reason}</span>
                )}
                {quote.decline_detail && (
                  <p className="mt-1 text-sm">{quote.decline_detail}</p>
                )}
              </div>
              <Button
                size="sm"
                onClick={() =>
                  router.push(`/quotes/${id}/edit?revise=true`)
                }
              >
                Revise &amp; Resend
              </Button>
            </div>
          </AlertDescription>
        </Alert>
      )}

      {quote.status === "expired" && (
        <Alert className="bg-amber-50 border-l-4 border-amber-400 text-amber-800">
          <AlertDescription className="text-amber-800">
            <div className="flex items-start justify-between gap-4 flex-wrap">
              <div>
                <strong>This quote expired on</strong>{" "}
                {quote.expiry_date
                  ? new Date(quote.expiry_date).toLocaleDateString()
                  : "unknown date"}
                . The client can no longer approve it.
              </div>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  onClick={() => setExtendDialogOpen(true)}
                >
                  Extend Expiry
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() =>
                    router.push(`/quotes/${id}/edit?revise=true`)
                  }
                >
                  Revise
                </Button>
              </div>
            </div>
          </AlertDescription>
        </Alert>
      )}

      {/* Two-column grid */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        {/* ------------------------------------------------------------------ */}
        {/* Main column                                                         */}
        {/* ------------------------------------------------------------------ */}
        <div className="space-y-6">
          {/* Line Items Card */}
          <Card>
            <CardHeader>
              <CardTitle>Line Items</CardTitle>
            </CardHeader>
            <CardContent>
              {quote.line_items.length === 0 ? (
                <p className="text-sm text-gray-500">No line items added.</p>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Type
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Description
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide text-right">
                        Qty
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                        Unit
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide text-right">
                        Unit Price
                      </TableHead>
                      <TableHead className="text-xs font-semibold text-gray-500 uppercase tracking-wide text-right">
                        Total
                      </TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {quote.line_items.map((item) => {
                      const lineTotal =
                        Number(item.quantity) * Number(item.unit_price);
                      return (
                        <TableRow key={item.id}>
                          <TableCell className="py-2 px-4 text-xs capitalize text-gray-600">
                            {item.item_type}
                          </TableCell>
                          <TableCell className="py-2 px-4 text-sm text-gray-700">
                            {item.description}
                          </TableCell>
                          <TableCell className="py-2 px-4 font-mono text-sm text-gray-900 text-right">
                            {item.quantity}
                          </TableCell>
                          <TableCell className="py-2 px-4 text-sm text-gray-500">
                            {item.unit}
                          </TableCell>
                          <TableCell className="py-2 px-4 font-mono text-sm text-gray-900 text-right">
                            ${Number(item.unit_price).toFixed(2)}
                          </TableCell>
                          <TableCell className="py-2 px-4 font-mono text-sm text-gray-900 text-right">
                            ${lineTotal.toFixed(2)}
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              )}

              {/* Financial summary footer */}
              <div className="mt-4 space-y-1 border-t pt-4">
                <div className="flex justify-between text-sm text-gray-600">
                  <span>Subtotal</span>
                  <span className="font-mono">
                    ${Number(quote.subtotal).toFixed(2)}
                  </span>
                </div>
                {Number(quote.discount_amount) > 0 && (
                  <div className="flex justify-between text-sm text-gray-600">
                    <span>
                      Discount
                      {quote.discount_type === "percent"
                        ? ` (${quote.discount_value}%)`
                        : ""}
                    </span>
                    <span className="font-mono text-red-600">
                      -${Number(quote.discount_amount).toFixed(2)}
                    </span>
                  </div>
                )}
                <div className="flex justify-between text-sm text-gray-600">
                  <span>Tax ({quote.tax_rate}%)</span>
                  <span className="font-mono">
                    ${Number(quote.tax_amount).toFixed(2)}
                  </span>
                </div>
                <div className="flex justify-between text-base font-semibold text-gray-900 pt-1 border-t">
                  <span>Total</span>
                  <span className="font-mono">
                    ${Number(quote.total).toFixed(2)}
                  </span>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Admin Notes Card */}
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

          {/* Activity Log Card */}
          <Card>
            <CardHeader>
              <CardTitle>Activity</CardTitle>
            </CardHeader>
            <CardContent>
              {activityEvents.length === 0 ? (
                <p className="text-sm text-gray-500">No activity yet.</p>
              ) : (
                <ul className="space-y-3">
                  {activityEvents.map((event, idx) => (
                    <li key={idx} className="flex items-start gap-3">
                      <StatusBadge status={event.status} size="sm" />
                      <div className="flex-1 min-w-0">
                        <div className="text-xs text-gray-500">
                          {new Date(event.date).toLocaleString()}
                        </div>
                        <div className="text-sm text-gray-700">{event.label}</div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>

        {/* ------------------------------------------------------------------ */}
        {/* Sidebar column                                                      */}
        {/* ------------------------------------------------------------------ */}
        <div className="space-y-4">
          {/* Status + Actions Card */}
          <Card>
            <CardHeader>
              <CardTitle>Status</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {/* Status stepper */}
              <StatusStepper currentStatus={quote.status} />

              {/* Context-sensitive action buttons */}
              <div className="flex flex-col gap-2">
                {quote.status === "draft" && (
                  <>
                    <Button
                      size="sm"
                      onClick={() => setSendDialogOpen(true)}
                      disabled={sendMutation.isPending}
                    >
                      Send Quote
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => router.push(`/quotes/${id}/edit`)}
                    >
                      Edit
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={handleDownloadPdf}
                      disabled={pdfDownloading}
                    >
                      Download PDF
                    </Button>
                  </>
                )}

                {(quote.status === "sent" || quote.status === "viewed") && (
                  <>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() =>
                        router.push(`/quotes/${id}/edit?revise=true`)
                      }
                    >
                      Revise
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setExtendDialogOpen(true)}
                    >
                      Extend Expiry
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={handleDownloadPdf}
                      disabled={pdfDownloading}
                    >
                      Download PDF
                    </Button>
                  </>
                )}

                {quote.status === "approved" && (
                  <>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={handleDownloadPdf}
                      disabled={pdfDownloading}
                    >
                      Download PDF
                    </Button>
                    {job?.status === "complete" && (
                      <Button
                        size="sm"
                        onClick={() => generateInvoiceMutation.mutate()}
                        disabled={generateInvoiceMutation.isPending}
                      >
                        Generate Invoice
                      </Button>
                    )}
                  </>
                )}

                {quote.status === "declined" && (
                  <>
                    <Button
                      size="sm"
                      onClick={() =>
                        router.push(`/quotes/${id}/edit?revise=true`)
                      }
                    >
                      Revise &amp; Resend
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={handleDownloadPdf}
                      disabled={pdfDownloading}
                    >
                      Download PDF
                    </Button>
                  </>
                )}

                {quote.status === "expired" && (
                  <>
                    <Button
                      size="sm"
                      onClick={() => setExtendDialogOpen(true)}
                    >
                      Extend Expiry
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() =>
                        router.push(`/quotes/${id}/edit?revise=true`)
                      }
                    >
                      Revise
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={handleDownloadPdf}
                      disabled={pdfDownloading}
                    >
                      Download PDF
                    </Button>
                  </>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Quote Info Card */}
          <Card>
            <CardHeader>
              <CardTitle>Quote Details</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Client
                </p>
                {job?.client_id ? (
                  <Link
                    href={`/clients/${job.client_id}`}
                    className="text-sm text-indigo-600 hover:text-indigo-800 hover:underline"
                  >
                    {job.client_name ?? job.client_id.slice(0, 8)}
                  </Link>
                ) : (
                  <p className="text-sm text-gray-900">
                    {job?.client_name ?? "—"}
                  </p>
                )}
              </div>

              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Job
                </p>
                <Link
                  href={`/jobs/${quote.job_id}`}
                  className="text-sm text-indigo-600 hover:underline truncate block max-w-full"
                >
                  {job?.description ?? quote.job_id.slice(0, 8)}
                </Link>
              </div>

              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Expiry Date
                </p>
                <p className="text-sm text-gray-900">
                  {quote.expiry_date
                    ? new Date(quote.expiry_date).toLocaleDateString()
                    : "No expiry"}
                </p>
              </div>

              {quote.viewed_at && (
                <div>
                  <p className="text-xs text-green-600">
                    Viewed by client on{" "}
                    {new Date(quote.viewed_at).toLocaleDateString()}
                  </p>
                </div>
              )}

              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Revision
                </p>
                <p className="text-sm text-gray-900">v{quote.revision_number}</p>
              </div>

              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Created
                </p>
                <p className="text-sm text-gray-900">
                  {new Date(quote.created_at).toLocaleDateString()}
                </p>
              </div>
            </CardContent>
          </Card>

          {/* Financial Summary Card */}
          <Card>
            <CardHeader>
              <CardTitle>Financial Summary</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <div className="flex justify-between text-sm text-gray-600">
                <span>Subtotal</span>
                <span className="font-mono">
                  ${Number(quote.subtotal).toFixed(2)}
                </span>
              </div>
              {Number(quote.discount_amount) > 0 && (
                <div className="flex justify-between text-sm text-gray-600">
                  <span>
                    Discount
                    {quote.discount_type === "percent"
                      ? ` (${quote.discount_value}%)`
                      : ""}
                  </span>
                  <span className="font-mono text-red-600">
                    -${Number(quote.discount_amount).toFixed(2)}
                  </span>
                </div>
              )}
              <div className="flex justify-between text-sm text-gray-600">
                <span>Tax ({quote.tax_rate}%)</span>
                <span className="font-mono">
                  ${Number(quote.tax_amount).toFixed(2)}
                </span>
              </div>
              <div className="flex justify-between text-base font-bold text-gray-900 pt-2 border-t">
                <span>Total</span>
                <span className="font-mono text-lg">
                  ${Number(quote.total).toFixed(2)}
                </span>
              </div>
            </CardContent>
          </Card>

          {/* Linked Invoice Card (only when approved and invoice exists) */}
          {linkedInvoice && (
            <Card>
              <CardHeader>
                <CardTitle>Linked Invoice</CardTitle>
              </CardHeader>
              <CardContent>
                <Link
                  href={`/invoices/${linkedInvoice.id}`}
                  className="text-sm text-indigo-600 hover:underline block mb-1"
                >
                  Invoice #{linkedInvoice.invoice_number}
                </Link>
                <div className="flex items-center justify-between">
                  <span className="font-mono text-sm text-gray-900">
                    ${Number(linkedInvoice.total).toFixed(2)}
                  </span>
                  <StatusBadge status={linkedInvoice.status} size="sm" />
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </div>

      {/* -------------------------------------------------------------------- */}
      {/* Send Quote Confirmation Dialog                                        */}
      {/* -------------------------------------------------------------------- */}
      <Dialog open={sendDialogOpen} onOpenChange={setSendDialogOpen}>
        <DialogContent showCloseButton>
          <DialogHeader>
            <DialogTitle>
              Send quote to {job?.client_name ?? "client"}?
            </DialogTitle>
          </DialogHeader>
          <p className="text-sm text-gray-600">
            They will receive a notification and can approve or decline this
            quote.
          </p>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setSendDialogOpen(false)}
              disabled={sendMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              onClick={() => sendMutation.mutate()}
              disabled={sendMutation.isPending}
            >
              Send Quote
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* -------------------------------------------------------------------- */}
      {/* Extend Expiry Dialog                                                  */}
      {/* -------------------------------------------------------------------- */}
      <Dialog open={extendDialogOpen} onOpenChange={setExtendDialogOpen}>
        <DialogContent showCloseButton>
          <DialogHeader>
            <DialogTitle>Extend Expiry Date</DialogTitle>
          </DialogHeader>
          <div className="space-y-2">
            <label className="text-xs font-semibold text-gray-700">
              New expiry date
            </label>
            <input
              type="date"
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              value={newExpiryDate}
              onChange={(e) => setNewExpiryDate(e.target.value)}
              min={new Date().toISOString().split("T")[0]}
            />
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => {
                setExtendDialogOpen(false);
                setNewExpiryDate("");
              }}
              disabled={extendMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              onClick={() => {
                if (newExpiryDate) extendMutation.mutate(newExpiryDate);
              }}
              disabled={!newExpiryDate || extendMutation.isPending}
            >
              Extend Expiry
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
