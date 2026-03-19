"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { apiGet, apiPatch, apiPost, apiFetchRaw } from "@/lib/api-client";
import type { Invoice, Job, InvoiceLineItem, ItemType, DiscountType } from "@/types/api";
import { StatusBadge } from "@/components/shared/status-badge";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Alert, AlertDescription } from "@/components/ui/alert";
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
          <div className="rounded-xl bg-gray-100 h-32" />
        </div>
        <div className="space-y-4">
          <div className="rounded-xl bg-gray-100 h-36" />
          <div className="rounded-xl bg-gray-100 h-32" />
          <div className="rounded-xl bg-gray-100 h-40" />
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Editable line items state
// ---------------------------------------------------------------------------

interface EditableLineItem {
  id: string;
  item_type: ItemType;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
  sort_order: number;
}

function lineItemsFromInvoice(lineItems: InvoiceLineItem[]): EditableLineItem[] {
  return lineItems.map((li) => ({
    id: li.id,
    item_type: li.item_type,
    description: li.description,
    quantity: li.quantity,
    unit: li.unit,
    unit_price: li.unit_price,
    sort_order: li.sort_order,
  }));
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function InvoiceDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

  // --- Payment form state ---
  const [showPaymentForm, setShowPaymentForm] = useState(false);
  const [paymentAmount, setPaymentAmount] = useState("");
  const [paymentError, setPaymentError] = useState<string | null>(null);

  // --- Editable line items state ---
  const [editableItems, setEditableItems] = useState<EditableLineItem[]>([]);
  const [editTaxRate, setEditTaxRate] = useState("");
  const [editDiscountType, setEditDiscountType] = useState<DiscountType | null>(null);
  const [editDiscountValue, setEditDiscountValue] = useState("");

  // --- Queries ---
  const {
    data: invoice,
    isLoading,
    isError,
  } = useQuery<Invoice>({
    queryKey: ["invoice", id],
    queryFn: () => apiGet<Invoice>(`/api/v1/invoices/${id}`),
  });

  const { data: job } = useQuery<Job>({
    queryKey: ["job", invoice?.job_id],
    queryFn: () => apiGet<Job>(`/api/v1/jobs/${invoice!.job_id}`),
    enabled: !!invoice?.job_id,
  });

  // Sync editable items when invoice loads
  useEffect(() => {
    if (invoice) {
      setEditableItems(lineItemsFromInvoice(invoice.line_items));
      setEditTaxRate(invoice.tax_rate);
      setEditDiscountType(invoice.discount_type);
      setEditDiscountValue(invoice.discount_value);
    }
  }, [invoice]);

  // --- Breadcrumb title ---
  useEffect(() => {
    if (invoice) {
      dispatch(setPageTitle(`Invoice #${invoice.invoice_number}`));
    }
    return () => {
      dispatch(setPageTitle(null));
    };
  }, [invoice, dispatch]);

  // --- Computed values ---
  const isOverdue =
    invoice &&
    (invoice.status === "unpaid" || invoice.status === "partially_paid") &&
    invoice.due_date !== null &&
    new Date(invoice.due_date) < new Date();

  const balance = invoice
    ? Number(invoice.total) - Number(invoice.amount_paid)
    : 0;

  const computedStatus = isOverdue
    ? "overdue"
    : invoice?.status ?? "unpaid";

  // --- Payment mutation ---
  const paymentMutation = useMutation<
    Invoice,
    Error,
    { status: string; amount_paid: number }
  >({
    mutationFn: (data) =>
      apiPatch<Invoice>(`/api/v1/invoices/${id}/payment`, data),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["invoice", id] });
      queryClient.invalidateQueries({ queryKey: ["invoices"] });
      const amt =
        typeof variables.amount_paid === "number"
          ? variables.amount_paid.toFixed(2)
          : variables.amount_paid;
      toast.success(`Payment of $${amt} recorded`);
      setShowPaymentForm(false);
      setPaymentAmount("");
      setPaymentError(null);
    },
    onError: () => {
      toast.error(
        "Failed to record payment. The amount was not saved. Try again.",
        { duration: Infinity }
      );
    },
  });

  // --- Save line items mutation ---
  const saveLineItemsMutation = useMutation<Invoice, Error, void>({
    mutationFn: () =>
      apiPatch<Invoice>(`/api/v1/invoices/${id}`, {
        line_items: editableItems,
        tax_rate: editTaxRate,
        discount_type: editDiscountType,
        discount_value: editDiscountValue,
      }),
    onSuccess: (updated) => {
      queryClient.setQueryData(["invoice", id], updated);
      queryClient.invalidateQueries({ queryKey: ["invoices"] });
      toast.success("Invoice changes saved");
    },
    onError: () => {
      toast.error("Failed to save changes. Try again.", { duration: Infinity });
    },
  });

  // --- Finalize mutation ---
  const finalizeMutation = useMutation<Invoice, Error, void>({
    mutationFn: () =>
      apiPost<Invoice>(`/api/v1/invoices/${id}/finalize`, {}),
    onSuccess: (updated) => {
      queryClient.setQueryData(["invoice", id], updated);
      queryClient.invalidateQueries({ queryKey: ["invoices"] });
      toast.success("Invoice finalized");
    },
    onError: () => {
      toast.error("Failed to finalize invoice. Try again.", { duration: Infinity });
    },
  });

  // --- Handlers ---
  function handleRecordPayment() {
    const amount = parseFloat(paymentAmount);
    if (isNaN(amount) || amount <= 0) {
      setPaymentError("Please enter a valid amount greater than 0.");
      return;
    }
    if (amount > balance) {
      setPaymentError("Amount cannot exceed remaining balance");
      return;
    }
    const newAmountPaid = Number(invoice!.amount_paid) + amount;
    const newStatus =
      newAmountPaid >= Number(invoice!.total) ? "paid" : "partially_paid";
    setPaymentError(null);
    paymentMutation.mutate({ status: newStatus, amount_paid: newAmountPaid });
  }

  function handleMarkFullyPaid() {
    if (!invoice) return;
    const total = Number(invoice.total);
    paymentMutation.mutate({ status: "paid", amount_paid: total });
  }

  async function downloadInvoicePdf() {
    if (!invoice) return;
    try {
      const resp = await apiFetchRaw(`/api/v1/invoices/${id}/pdf`);
      const blob = await resp.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `invoice-${invoice.invoice_number}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      toast.error("PDF download failed. Try again.", { duration: Infinity });
    }
  }

  function updateLineItem(
    idx: number,
    field: keyof EditableLineItem,
    value: string
  ) {
    setEditableItems((prev) =>
      prev.map((item, i) =>
        i === idx ? { ...item, [field]: value } : item
      )
    );
  }

  // --- Loading / error states ---
  if (isLoading) return <PageSkeleton />;

  if (isError || !invoice) {
    toast.error(
      "Failed to load invoice details. Check your connection and try again.",
      { duration: Infinity }
    );
    return (
      <div className="rounded-xl bg-white p-8 text-center ring-1 ring-foreground/10">
        <p className="text-sm text-gray-500">
          Failed to load invoice details. Check your connection and try again.
        </p>
      </div>
    );
  }

  const isFinalized = invoice.finalized_at !== null;
  const isPaid = invoice.status === "paid";

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

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

      {/* Overdue alert banner */}
      {isOverdue && (
        <Alert className="bg-red-50 border-l-4 border-red-400 text-red-800">
          <AlertDescription>
            This invoice is overdue. Due date:{" "}
            {invoice.due_date
              ? new Date(invoice.due_date).toLocaleDateString()
              : "—"}.
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
              {isFinalized ? (
                /* Read-only table for finalized invoices */
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
                    {invoice.line_items.map((item) => (
                      <TableRow key={item.id}>
                        <TableCell className="py-2 px-4 text-sm text-gray-600 capitalize">
                          {item.item_type}
                        </TableCell>
                        <TableCell className="py-2 px-4 text-sm text-gray-700">
                          {item.description}
                        </TableCell>
                        <TableCell className="py-2 px-4 font-mono text-sm text-gray-900 text-right">
                          {Number(item.quantity).toFixed(2)}
                        </TableCell>
                        <TableCell className="py-2 px-4 text-sm text-gray-600">
                          {item.unit}
                        </TableCell>
                        <TableCell className="py-2 px-4 font-mono text-sm text-gray-900 text-right">
                          ${Number(item.unit_price).toFixed(2)}
                        </TableCell>
                        <TableCell className="py-2 px-4 font-mono text-sm text-gray-900 text-right">
                          $
                          {(
                            Number(item.quantity) * Number(item.unit_price)
                          ).toFixed(2)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              ) : (
                /* Editable table for non-finalized invoices */
                <div className="space-y-3">
                  <Table>
                    <TableHeader>
                      <TableRow>
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
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {editableItems.map((item, idx) => (
                        <TableRow key={item.id}>
                          <TableCell className="py-1 px-2">
                            <Input
                              value={item.description}
                              onChange={(e) =>
                                updateLineItem(idx, "description", e.target.value)
                              }
                              className="h-8 text-sm"
                            />
                          </TableCell>
                          <TableCell className="py-1 px-2">
                            <Input
                              type="number"
                              value={item.quantity}
                              onChange={(e) =>
                                updateLineItem(idx, "quantity", e.target.value)
                              }
                              className="h-8 text-sm text-right w-20"
                            />
                          </TableCell>
                          <TableCell className="py-1 px-2">
                            <Input
                              value={item.unit}
                              onChange={(e) =>
                                updateLineItem(idx, "unit", e.target.value)
                              }
                              className="h-8 text-sm w-20"
                            />
                          </TableCell>
                          <TableCell className="py-1 px-2">
                            <Input
                              type="number"
                              step="0.01"
                              value={item.unit_price}
                              onChange={(e) =>
                                updateLineItem(idx, "unit_price", e.target.value)
                              }
                              className="h-8 text-sm text-right w-24"
                            />
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  <div className="flex gap-2 justify-end pt-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => saveLineItemsMutation.mutate()}
                      disabled={saveLineItemsMutation.isPending}
                    >
                      Save Changes
                    </Button>
                    <Button
                      size="sm"
                      onClick={() => finalizeMutation.mutate()}
                      disabled={finalizeMutation.isPending}
                    >
                      Finalize Invoice
                    </Button>
                  </div>
                </div>
              )}

              {/* Totals footer */}
              <div className="mt-4 border-t pt-4 space-y-1">
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">Subtotal</span>
                  <span className="font-mono text-gray-900">
                    ${Number(invoice.subtotal).toFixed(2)}
                  </span>
                </div>
                {Number(invoice.discount_amount) > 0 && (
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-500">
                      Discount
                      {invoice.discount_type === "percent"
                        ? ` (${Number(invoice.discount_value)}%)`
                        : ""}
                    </span>
                    <span className="font-mono text-gray-900">
                      -${Number(invoice.discount_amount).toFixed(2)}
                    </span>
                  </div>
                )}
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">
                    Tax ({Number(invoice.tax_rate)}%)
                  </span>
                  <span className="font-mono text-gray-900">
                    ${Number(invoice.tax_amount).toFixed(2)}
                  </span>
                </div>
                <div className="flex justify-between text-sm font-semibold border-t pt-2 mt-2">
                  <span className="text-gray-900">Total</span>
                  <span className="font-mono text-gray-900">
                    ${Number(invoice.total).toFixed(2)}
                  </span>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Payment Section Card */}
          <Card>
            <CardHeader>
              <CardTitle>Payment</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {/* Payment summary */}
              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <span className="text-xs text-gray-500 uppercase tracking-wide">
                    Total
                  </span>
                  <span className="font-mono text-sm text-gray-900">
                    ${Number(invoice.total).toFixed(2)}
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-xs text-gray-500 uppercase tracking-wide">
                    Paid
                  </span>
                  <span className="font-mono text-sm text-green-700">
                    ${Number(invoice.amount_paid).toFixed(2)}
                  </span>
                </div>
                <div className="flex justify-between items-center border-t pt-2">
                  <span className="text-xs text-gray-500 uppercase tracking-wide">
                    Balance
                  </span>
                  <span
                    className={cn(
                      "font-mono text-sm",
                      isOverdue ? "text-red-700" : "text-gray-900"
                    )}
                  >
                    ${balance.toFixed(2)}
                  </span>
                </div>
              </div>

              {/* Record payment inline form */}
              {!isPaid && (
                <>
                  {!showPaymentForm ? (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setShowPaymentForm(true)}
                    >
                      Record Payment
                    </Button>
                  ) : (
                    <div className="space-y-3 border rounded-lg p-3 bg-gray-50">
                      <p className="text-xs font-semibold text-gray-700">
                        Record Payment
                      </p>
                      <div className="flex items-center gap-2">
                        <span className="text-sm text-gray-600 w-6 shrink-0">$</span>
                        <Input
                          type="number"
                          step="0.01"
                          min="0.01"
                          max={balance}
                          placeholder="0.00"
                          value={paymentAmount}
                          onChange={(e) => {
                            setPaymentAmount(e.target.value);
                            setPaymentError(null);
                          }}
                          className="h-8 text-sm w-24"
                        />
                      </div>
                      {paymentError && (
                        <p className="text-xs text-red-600">{paymentError}</p>
                      )}
                      <div className="flex gap-2">
                        <Button
                          size="sm"
                          onClick={handleRecordPayment}
                          disabled={paymentMutation.isPending}
                        >
                          Save Payment
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => {
                            setShowPaymentForm(false);
                            setPaymentAmount("");
                            setPaymentError(null);
                          }}
                        >
                          Cancel
                        </Button>
                      </div>
                    </div>
                  )}
                </>
              )}
            </CardContent>
          </Card>
        </div>

        {/* ------------------------------------------------------------------ */}
        {/* Sidebar column                                                      */}
        {/* ------------------------------------------------------------------ */}
        <div className="space-y-4">
          {/* Status & Actions Card */}
          <Card>
            <CardHeader>
              <CardTitle>Actions</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <StatusBadge status={computedStatus} size="md" />

              <div className="flex flex-col gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  disabled={isPaid}
                  onClick={() => setShowPaymentForm(true)}
                >
                  Record Payment
                </Button>

                <Button
                  size="sm"
                  className="bg-indigo-600 hover:bg-indigo-700 text-white"
                  disabled={isPaid || paymentMutation.isPending}
                  onClick={handleMarkFullyPaid}
                >
                  Mark Fully Paid
                </Button>

                <Button
                  variant="outline"
                  size="sm"
                  onClick={downloadInvoicePdf}
                >
                  Download PDF
                </Button>

                {!isFinalized && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => finalizeMutation.mutate()}
                    disabled={finalizeMutation.isPending}
                  >
                    Finalize Invoice
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Payment Summary Card */}
          <Card>
            <CardHeader>
              <CardTitle>Payment Summary</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div>
                <p className="text-xs text-gray-500 uppercase tracking-wide">
                  Total
                </p>
                <p className="font-mono text-sm text-gray-900">
                  ${Number(invoice.total).toFixed(2)}
                </p>
              </div>
              <div>
                <p className="text-xs text-gray-500 uppercase tracking-wide">
                  Paid
                </p>
                <p className="font-mono text-sm text-green-700">
                  ${Number(invoice.amount_paid).toFixed(2)}
                </p>
              </div>
              <div className="border-t pt-3">
                <p className="text-xs text-gray-500 uppercase tracking-wide">
                  Balance
                </p>
                <p
                  className={cn(
                    "font-mono text-sm",
                    isOverdue ? "text-red-700" : "text-gray-900"
                  )}
                >
                  ${balance.toFixed(2)}
                </p>
              </div>
            </CardContent>
          </Card>

          {/* Invoice Info Card */}
          <Card>
            <CardHeader>
              <CardTitle>Invoice Details</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {/* Due date */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Due Date
                </p>
                <p
                  className={cn(
                    "text-sm",
                    isOverdue
                      ? "text-red-600 font-medium"
                      : "text-gray-900"
                  )}
                >
                  {invoice.due_date
                    ? new Date(invoice.due_date).toLocaleDateString()
                    : "—"}
                </p>
              </div>

              {/* Issued date */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Issued
                </p>
                <p className="text-sm text-gray-900">
                  {new Date(invoice.issued_at).toLocaleDateString()}
                </p>
              </div>

              {/* Finalized date */}
              {invoice.finalized_at && (
                <div>
                  <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Finalized
                  </p>
                  <p className="text-sm text-gray-900">
                    {new Date(invoice.finalized_at).toLocaleDateString()}
                  </p>
                </div>
              )}

              {/* Job link */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Job
                </p>
                <Link
                  href={`/jobs/${invoice.job_id}`}
                  className="text-sm text-indigo-600 hover:underline"
                >
                  {job?.description ?? invoice.job_id.slice(0, 8)}
                </Link>
              </div>

              {/* Client */}
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
                  <p className="text-sm text-gray-900">{job?.client_name ?? "—"}</p>
                )}
              </div>

              {/* Linked quote */}
              {invoice.quote_id && (
                <div>
                  <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Quote
                  </p>
                  <Link
                    href={`/quotes/${invoice.quote_id}`}
                    className="text-sm text-indigo-600 hover:underline"
                  >
                    View Quote
                  </Link>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
