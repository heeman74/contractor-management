import type { Invoice } from "@/types/api";

export function isInvoiceOverdue(invoice: Invoice): boolean {
  const isUnsettled =
    invoice.status === "unpaid" || invoice.status === "partially_paid";
  return (
    isUnsettled &&
    invoice.due_date !== null &&
    new Date(invoice.due_date) < new Date()
  );
}

export function invoiceBalance(invoice: Invoice): number {
  return Number(invoice.total) - Number(invoice.amount_paid);
}
