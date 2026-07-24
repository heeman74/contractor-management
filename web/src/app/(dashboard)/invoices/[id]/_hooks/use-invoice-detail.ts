import { useEffect, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet, apiPatch, apiPost } from "@/lib/api-client";
import { downloadFileFromApi } from "@/lib/download-file";
import type { Invoice, Job, DiscountType } from "@/types/api";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";
import { formatCurrency } from "@/lib/format";
import {
  invoiceBalance,
  isInvoiceOverdue,
  toEditableLineItems,
  type EditableLineItem,
} from "../_lib/invoice-line-items";

export function useInvoiceDetail(id: string) {
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

  const [editableItems, setEditableItems] = useState<EditableLineItem[]>([]);
  const [editTaxRate, setEditTaxRate] = useState("");
  const [editDiscountType, setEditDiscountType] = useState<DiscountType | null>(
    null
  );
  const [editDiscountValue, setEditDiscountValue] = useState("");
  const [syncedInvoiceId, setSyncedInvoiceId] = useState<string | undefined>();

  // Queries -----------------------------------------------------------------

  const { data: invoice, isLoading, isError } = useQuery<Invoice>({
    queryKey: ["invoice", id],
    queryFn: () => apiGet<Invoice>(`/api/v1/invoices/${id}`),
  });

  const { data: job } = useQuery<Job>({
    queryKey: ["job", invoice?.job_id],
    queryFn: () => apiGet<Job>(`/api/v1/jobs/${invoice!.job_id}`),
    enabled: !!invoice?.job_id,
  });

  // Seed editable state once per loaded invoice (render-phase sync, no effect).
  if (invoice && syncedInvoiceId !== invoice.id) {
    setSyncedInvoiceId(invoice.id);
    setEditableItems(toEditableLineItems(invoice.line_items));
    setEditTaxRate(invoice.tax_rate);
    setEditDiscountType(invoice.discount_type);
    setEditDiscountValue(invoice.discount_value);
  }

  useEffect(() => {
    if (invoice) dispatch(setPageTitle(`Invoice #${invoice.invoice_number}`));
    return () => {
      dispatch(setPageTitle(null));
    };
  }, [invoice, dispatch]);

  // Mutations ---------------------------------------------------------------

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
      toast.success(`Payment of ${formatCurrency(variables.amount_paid)} recorded`);
    },
    onError: () =>
      toast.error(
        "Failed to record payment. The amount was not saved. Try again.",
        { duration: Infinity }
      ),
  });

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
    onError: () =>
      toast.error("Failed to save changes. Try again.", { duration: Infinity }),
  });

  const finalizeMutation = useMutation<Invoice, Error, void>({
    mutationFn: () => apiPost<Invoice>(`/api/v1/invoices/${id}/finalize`, {}),
    onSuccess: (updated) => {
      queryClient.setQueryData(["invoice", id], updated);
      queryClient.invalidateQueries({ queryKey: ["invoices"] });
      toast.success("Invoice finalized");
    },
    onError: () =>
      toast.error("Failed to finalize invoice. Try again.", {
        duration: Infinity,
      }),
  });

  // Actions -----------------------------------------------------------------

  function recordPayment(amountInput: string): string | null {
    if (!invoice) return null;
    const amount = parseFloat(amountInput);
    if (Number.isNaN(amount) || amount <= 0) {
      return "Please enter a valid amount greater than 0.";
    }
    if (amount > invoiceBalance(invoice)) {
      return "Amount cannot exceed remaining balance";
    }
    const newAmountPaid = Number(invoice.amount_paid) + amount;
    const newStatus =
      newAmountPaid >= Number(invoice.total) ? "paid" : "partially_paid";
    paymentMutation.mutate({ status: newStatus, amount_paid: newAmountPaid });
    return null;
  }

  function markFullyPaid() {
    if (!invoice) return;
    paymentMutation.mutate({
      status: "paid",
      amount_paid: Number(invoice.total),
    });
  }

  async function downloadPdf() {
    if (!invoice) return;
    try {
      await downloadFileFromApi(
        `/api/v1/invoices/${id}/pdf`,
        `invoice-${invoice.invoice_number}.pdf`
      );
    } catch {
      toast.error("PDF download failed. Try again.", { duration: Infinity });
    }
  }

  function updateLineItem(
    index: number,
    field: keyof EditableLineItem,
    value: string
  ) {
    setEditableItems((prev) =>
      prev.map((item, i) => (i === index ? { ...item, [field]: value } : item))
    );
  }

  return {
    invoice,
    job,
    isLoading,
    isError,
    editableItems,
    isOverdue: invoice ? isInvoiceOverdue(invoice) : false,
    balance: invoice ? invoiceBalance(invoice) : 0,
    isFinalized: invoice?.finalized_at != null,
    isPaid: invoice?.status === "paid",
    isRecordingPayment: paymentMutation.isPending,
    isSaving: saveLineItemsMutation.isPending,
    isFinalizing: finalizeMutation.isPending,
    updateLineItem,
    recordPayment,
    markFullyPaid,
    downloadPdf,
    saveLineItems: () => saveLineItemsMutation.mutate(),
    finalize: () => finalizeMutation.mutate(),
  };
}
